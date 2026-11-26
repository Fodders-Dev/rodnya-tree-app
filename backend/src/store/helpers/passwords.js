const path = require("node:path");
const crypto = require("node:crypto");
const {
  hashPasswordAsync,
} = require("./persons-auth");

// Sync wrapper kept for migration code paths that already run inside
// a transaction and can't easily go async. New code should prefer
// `hashPasswordAsync`.
function hashPassword(password, salt = crypto.randomBytes(16).toString("hex")) {
  const derivedKey = crypto.scryptSync(password, salt, 64).toString("hex");
  return {
    salt,
    passwordHash: derivedKey,
  };
}

function verifyPasswordAsync(password, user) {
  if (!user?.passwordHash || !user?.passwordSalt) {
    return Promise.resolve(false);
  }

  return new Promise((resolve, reject) => {
    crypto.scrypt(password, user.passwordSalt, 64, (err, derivedKey) => {
      if (err) {
        reject(err);
        return;
      }
      const userHash = Buffer.from(user.passwordHash, "hex");
      // timingSafeEqual REQUIRES same-length buffers — guard so a
      // malformed stored hash can't crash the auth path. Different
      // lengths obviously don't match anyway.
      if (derivedKey.length !== userHash.length) {
        resolve(false);
        return;
      }
      resolve(crypto.timingSafeEqual(derivedKey, userHash));
    });
  });
}

function verifyPassword(password, user) {
  if (!user?.passwordHash || !user?.passwordSalt) {
    return false;
  }

  const derivedKey = crypto
    .scryptSync(password, user.passwordSalt, 64)
    .toString("hex");

  return crypto.timingSafeEqual(
    Buffer.from(derivedKey, "hex"),
    Buffer.from(user.passwordHash, "hex"),
  );
}

// Static dummy salt + zero-buffer hash used when authenticate() is
// called against an email that doesn't exist. Without it the no-user
// path returns in microseconds while the user-found path takes
// hundreds of ms for scrypt — the timing difference lets an attacker
// enumerate which emails are registered. Running a real scrypt against
// this constant salt takes the same time as a real verify, and
// timingSafeEqual keeps even that comparison constant-time. The
// result is always discarded; we never resolve `true`.
const _dummyAuthSalt = "rodnya-fake-salt-for-timing-equalization-only";

const _dummyAuthHash = Buffer.alloc(64);

function dummyVerifyForTimingParity(password) {
  return new Promise((resolve) => {
    crypto.scrypt(password, _dummyAuthSalt, 64, (err, derivedKey) => {
      if (err) {
        resolve(false);
        return;
      }
      try {
        crypto.timingSafeEqual(derivedKey, _dummyAuthHash);
      } catch (_) {
        // Ignore — only here for timing parity.
      }
      resolve(false);
    });
  });
}

module.exports = {
  hashPassword,
  verifyPasswordAsync,
  verifyPassword,
  _dummyAuthSalt,
  _dummyAuthHash,
  dummyVerifyForTimingParity,
};
