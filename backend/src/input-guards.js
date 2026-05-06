/**
 * Shared request-body validators. Centralizes the "cap a user-input
 * string before it lands in the DB / push payload / realtime
 * broadcast" logic so route handlers don't have to re-derive limits
 * on their own.
 *
 * Every helper returns `{ok: true, value}` on success or
 * `{ok: false, status, message}` on failure. Route handlers can
 * forward the failure shape directly:
 *
 *   const guard = enforceTextLimit(req.body?.text, {max: 4000});
 *   if (!guard.ok) {
 *     res.status(guard.status).json({message: guard.message});
 *     return;
 *   }
 *   const text = guard.value;
 *
 * Keeping the policy in one file means a future tightening (say,
 * dropping post content from 8 KB to 4 KB) is a one-line change
 * instead of a sweep across 20 routes.
 */

// ASCII control characters except `\t \n \r` which are legitimate
// inside long-form text. The remaining control bytes mostly serve as
// CRLF-injection vectors when the value lands in email subjects /
// push titles / log lines.
//
// eslint-disable-next-line no-control-regex
const _controlCharsExceptTabAndNewlines = /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/;

// Stricter form for fields that should be SINGLE-LINE — display
// names, titles, hashtags, etc. Drops every CR / LF too.
//
// eslint-disable-next-line no-control-regex
const _controlCharsAndNewlines = /[\x00-\x1f\x7f]/;

/**
 * Generic text guard.
 *
 *   max:           hard char cap. Default 16 384 (chat message);
 *                  callers pass smaller values for titles / names.
 *   allowMultiline: keep \n \r \t. False rejects any control char.
 *                  Default true.
 *   allowEmpty:    accept empty / whitespace-only input. Default false.
 *   trim:          .trim() before length check. Default true.
 */
function enforceTextLimit(rawValue, opts = {}) {
  const {
    max = 16_384,
    allowMultiline = true,
    allowEmpty = false,
    trim = true,
    fieldName = "text",
  } = opts;

  if (rawValue == null) {
    if (allowEmpty) return {ok: true, value: ""};
    return {
      ok: false,
      status: 400,
      message: `Поле «${fieldName}» обязательно`,
    };
  }

  let value = String(rawValue);
  if (trim) value = value.trim();

  if (!allowEmpty && value.length === 0) {
    return {
      ok: false,
      status: 400,
      message: `Поле «${fieldName}» не может быть пустым`,
    };
  }

  if (value.length > max) {
    return {
      ok: false,
      status: 400,
      message:
          `Поле «${fieldName}» слишком длинное (максимум ${max} символов)`,
    };
  }

  const controlPattern = allowMultiline
    ? _controlCharsExceptTabAndNewlines
    : _controlCharsAndNewlines;
  if (controlPattern.test(value)) {
    return {
      ok: false,
      status: 400,
      message: `Поле «${fieldName}» содержит недопустимые символы`,
    };
  }

  return {ok: true, value};
}

/**
 * Validates a non-negative integer that's used as a duration (seconds,
 * milliseconds, etc.). Caps at the supplied `max` so an attacker
 * can't ship Number.MAX_SAFE_INTEGER and get a "year 285 000" date.
 */
function enforceNonNegativeInt(rawValue, {max, fieldName = "value"} = {}) {
  const numeric = Number(rawValue);
  if (!Number.isFinite(numeric) || numeric < 0 || !Number.isInteger(numeric)) {
    return {
      ok: false,
      status: 400,
      message: `Поле «${fieldName}» должно быть неотрицательным целым числом`,
    };
  }
  if (max != null && numeric > max) {
    return {
      ok: false,
      status: 400,
      message: `Поле «${fieldName}» превышает максимум ${max}`,
    };
  }
  return {ok: true, value: numeric};
}

/**
 * Caps an array length and runs each element through a per-item
 * validator. Returns the cleaned array on success.
 *
 *   enforceArrayCap([...], {
 *     max: 50,
 *     itemValidator: (raw) => enforceTextLimit(raw, {max: 256}),
 *   })
 */
function enforceArrayCap(rawValue, opts) {
  const {
    max,
    itemValidator,
    fieldName = "items",
    allowEmpty = true,
  } = opts;

  if (!Array.isArray(rawValue)) {
    if (rawValue == null && allowEmpty) return {ok: true, value: []};
    return {
      ok: false,
      status: 400,
      message: `Поле «${fieldName}» должно быть массивом`,
    };
  }
  if (rawValue.length > max) {
    return {
      ok: false,
      status: 400,
      message:
          `Поле «${fieldName}» содержит больше ${max} элементов`,
    };
  }
  if (!allowEmpty && rawValue.length === 0) {
    return {
      ok: false,
      status: 400,
      message: `Поле «${fieldName}» не может быть пустым`,
    };
  }

  const cleaned = [];
  for (let i = 0; i < rawValue.length; i += 1) {
    const itemGuard = itemValidator(rawValue[i], i);
    if (!itemGuard.ok) {
      return {
        ok: false,
        status: itemGuard.status || 400,
        message:
            `${fieldName}[${i}]: ${itemGuard.message || "недопустимое значение"}`,
      };
    }
    cleaned.push(itemGuard.value);
  }
  return {ok: true, value: cleaned};
}

/**
 * Bounded URL guard. Rejects javascript: / data: / file: schemes —
 * even though we never `eval` user-supplied URLs, downstream Flutter
 * web could open one in a hyperlink and execute attacker JS in our
 * origin. Whitelisted schemes: http(s) and our own custom OAuth
 * scheme. Length capped at 2 048 chars (RFC 3986 practical limit
 * on most browsers).
 */
function enforceSafeUrl(rawValue, opts = {}) {
  const {
    fieldName = "url",
    allowEmpty = true,
    allowedSchemes = ["http", "https"],
    max = 2048,
  } = opts;

  if (rawValue == null || rawValue === "") {
    if (allowEmpty) return {ok: true, value: null};
    return {
      ok: false,
      status: 400,
      message: `Поле «${fieldName}» обязательно`,
    };
  }

  const str = String(rawValue).trim();
  if (str.length > max) {
    return {
      ok: false,
      status: 400,
      message: `Поле «${fieldName}» слишком длинное`,
    };
  }

  // eslint-disable-next-line no-control-regex
  if (/[\x00-\x1f\x7f]/.test(str)) {
    return {
      ok: false,
      status: 400,
      message: `Поле «${fieldName}» содержит недопустимые символы`,
    };
  }

  const schemeMatch = /^([a-z][a-z0-9+.-]*):/i.exec(str);
  if (!schemeMatch) {
    return {
      ok: false,
      status: 400,
      message: `Поле «${fieldName}» должно быть полным URL`,
    };
  }
  const scheme = schemeMatch[1].toLowerCase();
  if (!allowedSchemes.includes(scheme)) {
    return {
      ok: false,
      status: 400,
      message:
          `Поле «${fieldName}» использует недопустимую схему (${scheme})`,
    };
  }

  return {ok: true, value: str};
}

module.exports = {
  enforceTextLimit,
  enforceNonNegativeInt,
  enforceArrayCap,
  enforceSafeUrl,
};
