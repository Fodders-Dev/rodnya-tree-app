/**
 * Pluggable backends for the rate-limit middleware in app.js.
 *
 * The contract:
 *
 *   class XxxRateLimitBackend {
 *     // Bump the bucket for `key` and return its current state.
 *     // Implementations must atomically: read current count, reset
 *     // it if the resetAt has passed, increment by one, write back,
 *     // and return the post-increment {count, resetAt}.
 *     async incr(key, windowMs) -> {count: number, resetAt: number /  ms epoch /};
 *
 *     // Drop a bucket explicitly. Used by the periodic cleanup
 *     // sweep to garbage-collect expired buckets when the in-memory
 *     // map grows too large.
 *     async evict(key) -> void;
 *
 *     // Optional. Returns the current bucket count without bumping.
 *     // Used only by /admin/runtime introspection. Implementations
 *     // that don't need it can return null.
 *     async peek(key) -> {count: number, resetAt: number} | null;
 *   }
 *
 * Two implementations live here:
 *
 *   * InMemoryRateLimitBackend — Map<string, bucket> in the process.
 *     Default. Correct for the current single-process production
 *     deploy. Loses state on restart and per-process state is
 *     duplicated in multi-replica deploys.
 *
 *   * RedisRateLimitBackend — sketch only. Not currently wired up
 *     because we don't run Redis in production. When the backend
 *     scales out to multiple processes / replicas, instantiate this
 *     and pass via `createApp({rateLimitBackend})`.
 */

class InMemoryRateLimitBackend {
  constructor() {
    this._buckets = new Map();
  }

  async incr(key, windowMs) {
    const now = Date.now();
    const existing = this._buckets.get(key);
    const bucket = existing && existing.resetAt > now
      ? existing
      : {count: 0, resetAt: now + windowMs};
    bucket.count += 1;
    this._buckets.set(key, bucket);
    return {count: bucket.count, resetAt: bucket.resetAt};
  }

  async evict(key) {
    this._buckets.delete(key);
  }

  async peek(key) {
    const bucket = this._buckets.get(key);
    if (!bucket) return null;
    return {count: bucket.count, resetAt: bucket.resetAt};
  }

  // Test / introspection helper. Not part of the contract.
  get size() {
    return this._buckets.size;
  }

  // Periodic GC sweep — called from the rate-limit middleware to
  // bound memory under sustained load. Drops buckets whose window
  // has already passed.
  sweepExpired(nowMs = Date.now()) {
    let removed = 0;
    for (const [key, bucket] of this._buckets.entries()) {
      if (!bucket || bucket.resetAt <= nowMs) {
        this._buckets.delete(key);
        removed += 1;
      }
    }
    return removed;
  }
}

/**
 * Sketch only — not used in production. Documents what a Redis-backed
 * implementation would look like. The shape mirrors what
 * `rate-limit-redis` and similar libraries already provide; we keep
 * this here so a future scale-out PR can drop in `ioredis` and wire it
 * up via createApp's `rateLimitBackend` parameter without redesigning
 * the middleware.
 *
 * Pseudo-code for the atomic increment using the standard MULTI/EXEC
 * pattern (or a single Lua script for true atomicity):
 *
 *   const key = `rl:${bucket}:${ip}`;
 *   await redis.eval(`
 *     local count = redis.call('INCR', KEYS[1])
 *     if count == 1 then
 *       redis.call('PEXPIRE', KEYS[1], ARGV[1])
 *     end
 *     local ttl = redis.call('PTTL', KEYS[1])
 *     return {count, ttl}
 *   `, 1, key, windowMs)
 *
 * The script returns [count, ttl_ms]; resetAt = Date.now() + ttl.
 */
class RedisRateLimitBackend {
  constructor({redis, prefix = "rl:"}) {
    if (!redis || typeof redis.eval !== "function") {
      throw new Error(
        "RedisRateLimitBackend requires an ioredis-style client with .eval()",
      );
    }
    this._redis = redis;
    this._prefix = prefix;
  }

  async incr(key, windowMs) {
    const fullKey = `${this._prefix}${key}`;
    const result = await this._redis.eval(
      `
      local count = redis.call('INCR', KEYS[1])
      if count == 1 then
        redis.call('PEXPIRE', KEYS[1], ARGV[1])
      end
      local ttl = redis.call('PTTL', KEYS[1])
      return {count, ttl}
      `,
      1,
      fullKey,
      windowMs,
    );
    const count = Number(Array.isArray(result) ? result[0] : 0);
    const ttlMs = Number(Array.isArray(result) ? result[1] : windowMs);
    const resetAt = Date.now() + Math.max(ttlMs, 0);
    return {count, resetAt};
  }

  async evict(key) {
    await this._redis.del(`${this._prefix}${key}`);
  }

  async peek(key) {
    const value = await this._redis.get(`${this._prefix}${key}`);
    if (value == null) return null;
    const ttlMs = await this._redis.pttl(`${this._prefix}${key}`);
    return {
      count: Number(value),
      resetAt: Date.now() + Math.max(Number(ttlMs) || 0, 0),
    };
  }
}

module.exports = {
  InMemoryRateLimitBackend,
  RedisRateLimitBackend,
};
