package ledgerstore

import (
	"bytes"
	"context"
	"encoding/json"
	"io"

	"github.com/minio/minio-go/v7"

	"github.com/AtomiCloud/diene.go-base/lib/operator/ledger"
)

type MinioStore struct {
	client *minio.Client
	bucket string
	prefix string
}

func NewMinioStore(client *minio.Client, bucket, prefix string) *MinioStore {
	return &MinioStore{client: client, bucket: bucket, prefix: prefix}
}

func (s *MinioStore) EnsureBucket(ctx context.Context) error {
	exists, err := s.client.BucketExists(ctx, s.bucket)
	if err != nil {
		return err
	}
	if exists {
		return nil
	}
	if err := s.client.MakeBucket(ctx, s.bucket, minio.MakeBucketOptions{}); err != nil {
		if IsBucketExistsRace(err) {
			return nil
		}
		return err
	}
	return nil
}

// IsBucketExistsRace is true when a concurrent manager won MakeBucket; treat it as success.
func IsBucketExistsRace(err error) bool {
	switch minio.ToErrorResponse(err).Code {
	case "BucketAlreadyOwnedByYou", "BucketAlreadyExists":
		return true
	default:
		return false
	}
}

func (s *MinioStore) objectName(key string) string {
	return s.prefix + key
}

func (s *MinioStore) Get(ctx context.Context, key string) (ledger.Entry, bool, error) {
	obj, err := s.client.GetObject(ctx, s.bucket, s.objectName(key), minio.GetObjectOptions{})
	if err != nil {
		return ledger.Entry{}, false, err
	}
	defer func() { _ = obj.Close() }()

	data, err := io.ReadAll(obj)
	if err != nil {
		if minio.ToErrorResponse(err).Code == "NoSuchKey" {
			return ledger.Entry{}, false, nil
		}
		return ledger.Entry{}, false, err
	}

	var entry ledger.Entry
	if err := json.Unmarshal(data, &entry); err != nil {
		return ledger.Entry{}, false, err
	}
	return entry, true, nil
}

func (s *MinioStore) Put(ctx context.Context, entry ledger.Entry) error {
	data, err := json.Marshal(entry)
	if err != nil {
		return err
	}
	_, err = s.client.PutObject(
		ctx, s.bucket, s.objectName(entry.Coordinate.Key()),
		bytes.NewReader(data), int64(len(data)),
		minio.PutObjectOptions{ContentType: "application/json"},
	)
	return err
}
