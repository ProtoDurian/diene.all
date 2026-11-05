// Package kv holds the Redis adapter for the note.Store port.
package kv

// DOMAIN WIRING: replaceable Note Redis adapter.
import (
	"context"

	"github.com/redis/go-redis/v9"
)

// RedisStore is a note.Store backed by one Redis client.
type RedisStore struct {
	client *redis.Client
}

// NewRedisStore connects a RedisStore to the Redis server at address.
func NewRedisStore(address string) *RedisStore {
	return &RedisStore{client: redis.NewClient(&redis.Options{Addr: address})}
}

// Save sets key to value with no expiry.
func (store *RedisStore) Save(ctx context.Context, key string, value string) error {
	return store.client.Set(ctx, key, value, 0).Err()
}

// Load returns the value stored at key.
func (store *RedisStore) Load(ctx context.Context, key string) (string, error) {
	return store.client.Get(ctx, key).Result()
}

// Close releases the Redis client.
func (store *RedisStore) Close() error {
	return store.client.Close()
}

// END DOMAIN WIRING
