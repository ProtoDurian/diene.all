package operator_test

import (
	"errors"
	"testing"

	"github.com/minio/minio-go/v7"
	"github.com/stretchr/testify/require"

	"github.com/AtomiCloud/diene.go-base/adapters/operator/ledgerstore"
)

func TestIsBucketExistsRace(t *testing.T) {
	// Arrange
	// Act
	// Assert
	require.True(t, ledgerstore.IsBucketExistsRace(minio.ErrorResponse{Code: "BucketAlreadyOwnedByYou"}))
	require.True(t, ledgerstore.IsBucketExistsRace(minio.ErrorResponse{Code: "BucketAlreadyExists"}))
	require.False(t, ledgerstore.IsBucketExistsRace(minio.ErrorResponse{Code: "AccessDenied"}))
	require.False(t, ledgerstore.IsBucketExistsRace(errors.New("dial tcp: connection refused")))
}
