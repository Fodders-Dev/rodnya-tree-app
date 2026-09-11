#!/usr/bin/env node
// SPEED-15 rollback: вернуть корзину deletedPersons из таблицы в блоб.
//
// Нужен ТОЛЬКО для отката бэкенда на код до SPEED-15: старый код читает
// корзину из блоба, а после миграции она живёт в таблице
// <table>_deleted_persons. Скрипт собирает АКТУАЛЬНОЕ содержимое таблицы
// (включая restore/hard-delete, случившиеся уже после миграции — restored
// строки восстанавливаются как есть, с полем restoredAt/restoredByUserId,
// как их видел бы старый FileStore-код), кладёт его в блоб и снимает
// маркер. Таблица очищается, чтобы повторный запуск нового кода начал
// миграцию заново.
//
// Запуск (на сервере, при ОСТАНОВЛЕННОМ бэкенде):
//   RODNYA_POSTGRES_URL=postgres://... node scripts/restore-deleted-persons-to-blob.js
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

    const marker = state?.migrationStatus?.deletedPersonsToTables;
    if (marker !== "complete-v1" && !process.argv.includes("--force")) {
      throw new Error(
        `миграция не выполнялась (маркер='${marker || "нет"}') — откатывать нечего; ` +
          "если уверены, повторите с --force",
      );
    }

    const deletedPersons = (
      await client.query(`SELECT row_data FROM ${q("deleted_persons")} ORDER BY deleted_at, id`)
    ).rows.map((row) => parseJson(row.row_data));

    console.log(
      `Таблица: deletedPersons=${deletedPersons.length}; ` +
        `блоб сейчас: deletedPersons=${(state.deletedPersons || []).length}, ` +
        `маркер=${marker || "нет"}`,
    );
    if (dryRun) {
      console.log("--dry-run: ничего не изменено");
      return;
    }

    const nextState = {
      ...state,
      deletedPersons,
      migrationStatus: {...(state.migrationStatus || {})},
    };
    delete nextState.migrationStatus.deletedPersonsToTables;

    await client.query("BEGIN");
    await client.query(
      `UPDATE ${stateTable}
          SET data = $2::jsonb, updated_at = NOW(), version = version + 1
        WHERE id = $1`,
      [rowId, JSON.stringify(nextState)],
    );
    await client.query(`DELETE FROM ${q("deleted_persons")}`);
    await client.query(
      `UPDATE ${q("deleted_persons_backups")}
          SET id = id || '-restored-' || $1
        WHERE id = 'pre-migration-complete-v1'`,
      [Date.now().toString(36)],
    );
    await client.query("COMMIT");
    console.log("Готово: deletedPersons возвращены в блоб, маркер снят, таблица очищена.");
    console.log("Теперь можно запускать бэкенд ЛЮБОЙ версии (старый — читает блоб,");
    console.log("новый — смигрирует в таблицу заново при старте).");
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
