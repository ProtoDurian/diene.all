package operator_test

import (
	"bytes"
	"context"
	"testing"

	"github.com/minio/minio-go/v7"
	miniocreds "github.com/minio/minio-go/v7/pkg/credentials"
	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/AtomiCloud/diene.go-base/adapters/operator/ledgerstore"
	"github.com/AtomiCloud/diene.go-base/lib/operator/ledger"
)

func startMinio(t *testing.T) *minio.Client {
	t.Helper()
	ctx := context.Background()
	container, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: testcontainers.ContainerRequest{
			Image:        "pgsty/minio:RELEASE.2026-08-04T00-00-00Z",
			Cmd:          []string{"server", "/data"},
			Env:          map[string]string{"MINIO_ROOT_USER": "minioadmin", "MINIO_ROOT_PASSWORD": "minioadmin"},
			ExposedPorts: []string{"9000/tcp"},
			WaitingFor:   wait.ForHTTP("/minio/health/live").WithPort("9000/tcp"),
		},
		Started: true,
	})
	require.NoError(t, err)
	t.Cleanup(func() { _ = container.Terminate(ctx) })

	endpoint, err := container.Endpoint(ctx, "")
	require.NoError(t, err)
	client, err := minio.New(endpoint, &minio.Options{
		Creds:  miniocreds.NewStaticV4("minioadmin", "minioadmin", ""),
		Secure: false,
	})
	require.NoError(t, err)
	return client
}

func coordinate(module string) ledger.Coordinate {
	return ledger.Coordinate{Platform: "diene", Landscape: "lapras", Class: "note", Module: module}
}

func TestMinioLedgerLifecycle(t *testing.T) {
	// Arrange
	ctx := context.Background()
	store := ledgerstore.NewMinioStore(startMinio(t), "operator-template-ledger", "notes/")
	require.NoError(t, store.EnsureBucket(ctx))

	// Act
	// Assert
	require.NoError(t, store.EnsureBucket(ctx))

	svc := ledger.NewService(store)
	coord := coordinate("alpha")

	// Act
	_, ok, err := store.Get(ctx, coord.Key())

	// Assert
	require.NoError(t, err)
	require.False(t, ok)

	// Act
	entry, err := svc.Intent(ctx, coord, "ext-alpha", "secret/notes/alpha")

	// Assert
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseIntent, entry.Phase)

	// Act
	entry, err = svc.Created(ctx, coord)

	// Assert
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseCreated, entry.Phase)

	// Act
	entry, err = svc.Confirm(ctx, coord)

	// Assert
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseConfirmed, entry.Phase)

	// Act
	require.NoError(t, svc.Orphan(ctx, coord))

	// Assert
	orphaned, _, _ := store.Get(ctx, coord.Key())
	require.Equal(t, ledger.PhaseOrphaned, orphaned.Phase)
	require.Equal(t, "ext-alpha", orphaned.ExternalID)

	// Act
	adopted, err := svc.Adopt(ctx, coord)

	// Assert
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseCreated, adopted.Phase)
	require.Equal(t, "ext-alpha", adopted.ExternalID)

	// Act
	confirmed, err := svc.Confirm(ctx, coord)

	// Assert
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseConfirmed, confirmed.Phase)

	// Act
	again, err := svc.Intent(ctx, coord, "ext-other", "other")

	// Assert
	require.NoError(t, err)
	require.Equal(t, "ext-alpha", again.ExternalID)
}

func TestMinioLedgerCorruptObject(t *testing.T) {
	// Arrange
	ctx := context.Background()
	client := startMinio(t)
	store := ledgerstore.NewMinioStore(client, "corrupt-bucket", "notes/")
	require.NoError(t, store.EnsureBucket(ctx))

	garbage := []byte("not json")
	_, err := client.PutObject(ctx, "corrupt-bucket", "notes/diene/lapras/note/beta", bytes.NewReader(garbage), int64(len(garbage)), minio.PutObjectOptions{})
	require.NoError(t, err)

	// Act
	_, _, err = store.Get(ctx, coordinate("beta").Key())

	// Assert
	require.Error(t, err)
}
