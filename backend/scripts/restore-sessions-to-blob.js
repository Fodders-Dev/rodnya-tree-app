#!/usr/bin/env node
// SPEED-15 rollback: вернуть sessions из auth_sessions обратно в блоб.
//
// Контекст, важный для понимания того, что откатывает этот скрипт: сама
// таблица auth_sessions (<table>_auth_sessions, SPEED-6/8a) была
// единственным источником данных на ЧТЕНИЕ уже ДО SPEED-15 — _read()
// подменяла data.sessions её содержимым на каждом пути. SPEED-15 лишь
// перестала ДОПОЛНИТЕЛЬНО писать те же сессии в JSONB-колонку на каждый
// _write() и научила _hydrateAuthProjectionTablesFromStateRow() (вызывается
// на КАЖДОМ старте процесса) не перестраивать таблицу ИЗ блоба, когда
// маркер стоит. Поэтому откат — это НЕ «взять бэкап», а «скопировать
// АКТУАЛЬНОЕ содержимое auth_sessions в блоб и снять маркер», иначе старый
// код (который перестраивает таблицу из блоба на каждом боте) стёр бы все
// сессии, созданные после миграции, при следующем же рестарте.
//
// Запуск (на сервере, при ОСТАНОВЛЕННОМ бэкенде):
//   RODNYA_POSTGRES_URL=postgres://... node scripts/restore-sessions-to-blob.js
//   ...или с LINEAGE_POSTGRES_URL / DATABASE_URL — как у самого бэкенда.
// Опции: --dry-run (только показать объёмы), --force (без маркера).

const {Client} = require("pg");

const url =
  process.env.RODNYA_POSTGRES_URL ||
  process.env.LINEAGE_POSTGRES_URL ||
  process.env.DATABASE_URL;
const schema = process.env.RODNYA_POSTGRES_SCHEMA || "public";
const table = process.env.RODNYA_POSTGRES_STATE_TABLE || "rodnya_state";
const rowId = process.env.RODNYA_POSTGRES_STATE_ROW_ID || "default";
const dryRun = process.argv.includes("--dry-run");

if (!url) {
  console.error("Не задан RODNYA_POSTGRES_URL / LINEAGE_POSTGRES_URL / DATABASE_URL");
  process.exit(1);
}

const q = (name) => `"${schema}"."${table}_${name}"`;
const stateTable = `"${schema}"."${table}"`;

const parseJson = (value) => (typeof value === "string" ? JSON.parse(value) : value);

(async () => {
  const client = new Client({connectionString: url});
  await client.connect();
  try {
    const stateResult = await client.query(
      `SELECT data FROM ${stateTable} WHERE id = $1`,
      [rowId],
    );
    if (stateResult.rows.length === 0) {
      throw new Error(`строка состояния id='${rowId}' не найдена`);
    }
    const state = parseJson(stateResult.rows[0].data);

    const marker = state?.migrationStatus?.sessionsOutOfBlob;
    if (marker !== "complete-v1" && !process.argv.includes("--force")) {
      throw new Error(
        `миграция не выполнялась (маркер='${marker || "нет"}') — откатывать нечего; ` +
          "если уверены, повторите с --force",
      );
    }

    // ИЗ ТАБЛИЦЫ (не из бэкапа) — она уже накопила все сессии, созданные
    // после миграции; бэкап — только точка «на момент миграции», для аудита.
    const sessions = (
      await client.query(
        `SELECT session_data FROM ${q("auth_sessions")} ORDER BY created_at NULLS FIRST, token`,
      )
    ).rows.map((row) => parseJson(row.session_data));

    console.log(
      `auth_sessions сейчас: ${sessions.length}; блоб сейчас: sessions=${(state.sessions || []).length}, ` +
        `маркер=${marker || "нет"}`,
    );
    if (dryRun) {
      console.log("--dry-run: ничего не изменено");
      return;
    }

    const nextState = {
      ...state,
      sessions,
      migrationStatus: {...(state.migrationStatus || {})},
    };
    delete nextState.migrationStatus.sessionsOutOfBlob;

    await client.query("BEGIN");
    // version + 1: кэш чтения (SPEED-8a) обязан увидеть новую строку.
    await client.query(
      `UPDATE ${stateTable}
          SET data = $2::jsonb, updated_at = NOW(), version = version + 1
        WHERE id = $1`,
      [rowId, JSON.stringify(nextState)],
    );
    // Таблицу auth_sessions НЕ трогаем — старый код (без SPEED-15) читает
    // сессии из неё же (SPEED-6/8a), просто вдобавок теперь и из блоба, и
    // будет перестраивать её из блоба на каждом следующем боте (что, раз
    // мы только что положили туда то же самое, — no-op).
    await client.query("COMMIT");
    console.log("Готово: sessions возвращены в блоб, маркер снят. auth_sessions не менялась.");
    console.log("Теперь можно запускать бэкенд ЛЮБОЙ версии (старый — перестраивает таблицу");
    console.log("из блоба на каждом боте, новый — снова смигрирует их вон из блоба).");
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch (_) {
      // соединение могло уже закрыться — исходная ошибка важнее
    }
    console.error("ОШИБКА:", error.message);
    process.exitCode = 1;
  } finally {
    await client.end();
  }
})();
