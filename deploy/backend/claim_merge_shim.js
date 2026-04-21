const http = require("node:http");

const port = Number(process.env.PORT || 8081);
const upstreamBaseUrl = process.env.CLAIM_SHIM_UPSTREAM || "http://127.0.0.1:8080";
const identityShimHeader = "x-rodnya-identity-shim";
const claimShimHeader = "x-rodnya-claim-shim";
const defaultCorsAllowHeaders = "authorization, content-type, if-none-match";
const defaultCorsAllowMethods = "GET, POST, PUT, PATCH, DELETE, OPTIONS";

function jsonHeaders(extra = {}) {
  return {
    "content-type": "application/json; charset=utf-8",
    ...extra,
  };
}

function resolveCorsHeaders(req, extra = {}) {
  const origin = String(req.headers.origin || "").trim();
  const requestedHeaders = String(
    req.headers["access-control-request-headers"] || "",
  ).trim();
  const requestedMethod = String(
    req.headers["access-control-request-method"] || "",
  ).trim();
  const varyValues = ["Origin", "Access-Control-Request-Headers", "Access-Control-Request-Method"];

  return {
    ...(origin ? {"access-control-allow-origin": origin} : {}),
    "access-control-allow-headers": requestedHeaders || defaultCorsAllowHeaders,
    "access-control-allow-methods": requestedMethod
      ? `${requestedMethod}, OPTIONS`
      : defaultCorsAllowMethods,
    "access-control-max-age": "600",
    vary: varyValues.join(", "),
    ...extra,
  };
}

function syntheticIdentityIdForUser(userId) {
  const normalizedUserId = typeof userId === "string" ? userId.trim() : "";
  return normalizedUserId ? `identity-${normalizedUserId}` : null;
}

function withSyntheticIdentity(person) {
  if (!person || typeof person !== "object") {
    return person;
  }

  if (person.identityId) {
    return person;
  }

  const syntheticIdentityId = syntheticIdentityIdForUser(person.userId);
  if (!syntheticIdentityId) {
    return person;
  }

  return {
    ...person,
    identityId: syntheticIdentityId,
  };
}

async function readJsonBody(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }

  if (!chunks.length) {
    return {};
  }

  const rawBody = Buffer.concat(chunks).toString("utf8").trim();
  if (!rawBody) {
    return {};
  }

  return JSON.parse(rawBody);
}

async function requestJson(path, {method = "GET", headers = {}, body} = {}) {
  const response = await fetch(`${upstreamBaseUrl}${path}`, {
    method,
    headers: {
      ...headers,
      ...(body === undefined ? {} : {"content-type": "application/json"}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const rawText = await response.text();
  const payload = rawText ? JSON.parse(rawText) : null;

  return {
    ok: response.ok,
    status: response.status,
    payload,
    headers: response.headers,
  };
}

function sendJson(req, res, statusCode, payload, extraHeaders = {}) {
  res.writeHead(statusCode, jsonHeaders(resolveCorsHeaders(req, extraHeaders)));
  res.end(payload === undefined ? "" : JSON.stringify(payload));
}

function sendNoContent(req, res, extraHeaders = {}) {
  res.writeHead(204, resolveCorsHeaders(req, extraHeaders));
  res.end();
}

async function proxyJsonEndpoint(req, res, {transformPayload} = {}) {
  let body;
  try {
    body =
      req.method === "GET" || req.method === "HEAD"
        ? undefined
        : await readJsonBody(req);
  } catch (error) {
    sendJson(req, res, 400, {message: "Некорректный JSON body"});
    return;
  }

  try {
    const upstream = await requestJson(req.url, {
      method: req.method,
      headers: {
        authorization: String(req.headers.authorization || "").trim(),
      },
      body,
    });

    const payload =
      typeof transformPayload === "function" && upstream.payload
        ? transformPayload(upstream.payload)
        : upstream.payload;

    sendJson(req, res, upstream.status, payload, {
      [identityShimHeader]: "1",
    });
  } catch (error) {
    sendJson(
      req,
      res,
      502,
      {
        message: "Не удалось проксировать JSON endpoint",
        details: error instanceof Error ? error.message : String(error),
      },
      {
        [identityShimHeader]: "1",
      },
    );
  }
}

async function migrateRelations({
  authorization,
  treeId,
  claimedPersonId,
  duplicatePersonId,
  relations,
}) {
  const duplicateRelations = relations.filter(
    (relation) =>
      relation.person1Id === duplicatePersonId ||
      relation.person2Id === duplicatePersonId,
  );

  let rewriteCount = 0;
  let nextRelations = [...relations];

  for (const relation of duplicateRelations) {
    const nextPerson1Id =
      relation.person1Id === duplicatePersonId
        ? claimedPersonId
        : relation.person1Id;
    const nextPerson2Id =
      relation.person2Id === duplicatePersonId
        ? claimedPersonId
        : relation.person2Id;

    if (nextPerson1Id !== nextPerson2Id) {
      const alreadyExists = nextRelations.some(
        (entry) =>
          entry.id !== relation.id &&
          entry.person1Id === nextPerson1Id &&
          entry.person2Id === nextPerson2Id &&
          entry.relation1to2 === relation.relation1to2 &&
          (entry.relation2to1 || null) === (relation.relation2to1 || null) &&
          Boolean(entry.isConfirmed) === Boolean(relation.isConfirmed),
      );

      if (!alreadyExists) {
        const createdRelation = await requestJson(`/v1/trees/${treeId}/relations`, {
          method: "POST",
          headers: {
            authorization,
          },
          body: {
            person1Id: nextPerson1Id,
            person2Id: nextPerson2Id,
            relation1to2: relation.relation1to2,
            relation2to1: relation.relation2to1,
            isConfirmed: relation.isConfirmed,
            marriageDate: relation.marriageDate,
            divorceDate: relation.divorceDate,
          },
        });

        if (!createdRelation.ok) {
          throw new Error(
            `Relation rewrite failed: ${createdRelation.status} ${JSON.stringify(createdRelation.payload)}`,
          );
        }

        nextRelations.push(createdRelation.payload.relation);
      }
    }

    const deletedRelation = await requestJson(
      `/v1/trees/${treeId}/relations/${relation.id}`,
      {
        method: "DELETE",
        headers: {
          authorization,
        },
      },
    );

    if (![200, 204].includes(deletedRelation.status)) {
      throw new Error(
        `Relation delete failed: ${deletedRelation.status} ${JSON.stringify(deletedRelation.payload)}`,
      );
    }

    nextRelations = nextRelations.filter((entry) => entry.id !== relation.id);
    rewriteCount += 1;
  }

  return {relations: nextRelations, rewriteCount};
}

async function mergeDuplicatePersons({authorization, treeId, claimedPersonId}) {
  const personsResponse = await requestJson(`/v1/trees/${treeId}/persons`, {
    headers: {authorization},
  });
  if (!personsResponse.ok) {
    throw new Error(
      `Persons fetch failed: ${personsResponse.status} ${JSON.stringify(personsResponse.payload)}`,
    );
  }

  const claimedPerson = personsResponse.payload?.persons?.find(
    (person) => person.id === claimedPersonId,
  );
  if (!claimedPerson || !claimedPerson.userId) {
    return {
      claimedPerson: claimedPerson || null,
      duplicatePersonIds: [],
      relationRewriteCount: 0,
      persons: personsResponse.payload?.persons || [],
    };
  }

  const duplicatePersons = (personsResponse.payload?.persons || []).filter(
    (person) =>
      person.userId === claimedPerson.userId && person.id !== claimedPersonId,
  );
  if (!duplicatePersons.length) {
    return {
      claimedPerson,
      duplicatePersonIds: [],
      relationRewriteCount: 0,
      persons: personsResponse.payload?.persons || [],
    };
  }

  const relationsResponse = await requestJson(`/v1/trees/${treeId}/relations`, {
    headers: {authorization},
  });
  if (!relationsResponse.ok) {
    throw new Error(
      `Relations fetch failed: ${relationsResponse.status} ${JSON.stringify(relationsResponse.payload)}`,
    );
  }

  let relations = relationsResponse.payload?.relations || [];
  let relationRewriteCount = 0;

  for (const duplicatePerson of duplicatePersons) {
    const relationMigration = await migrateRelations({
      authorization,
      treeId,
      claimedPersonId,
      duplicatePersonId: duplicatePerson.id,
      relations,
    });
    relations = relationMigration.relations;
    relationRewriteCount += relationMigration.rewriteCount;

    const deletedPerson = await requestJson(
      `/v1/trees/${treeId}/persons/${duplicatePerson.id}`,
      {
        method: "DELETE",
        headers: {
          authorization,
        },
      },
    );

    if (![200, 204].includes(deletedPerson.status)) {
      throw new Error(
        `Person delete failed: ${deletedPerson.status} ${JSON.stringify(deletedPerson.payload)}`,
      );
    }
  }

  const finalPersonsResponse = await requestJson(`/v1/trees/${treeId}/persons`, {
    headers: {authorization},
  });
  if (!finalPersonsResponse.ok) {
    throw new Error(
      `Final persons fetch failed: ${finalPersonsResponse.status} ${JSON.stringify(finalPersonsResponse.payload)}`,
    );
  }

  const finalClaimedPerson = finalPersonsResponse.payload?.persons?.find(
    (person) => person.id === claimedPersonId,
  );

  return {
    claimedPerson: finalClaimedPerson || claimedPerson,
    duplicatePersonIds: duplicatePersons.map((person) => person.id),
    relationRewriteCount,
    persons: finalPersonsResponse.payload?.persons || [],
  };
}

async function handleClaim(req, res) {
  let body;
  try {
    body = await readJsonBody(req);
  } catch (error) {
    sendJson(req, res, 400, {message: "Некорректный JSON body"});
    return;
  }

  const treeId = String(body?.treeId || "").trim();
  const personId = String(body?.personId || "").trim();
  const authorization = String(req.headers.authorization || "").trim();

  if (!treeId || !personId) {
    sendJson(req, res, 400, {message: "Нужны treeId и personId"});
    return;
  }

  if (!authorization) {
    sendJson(req, res, 401, {message: "Нужен authorization header"});
    return;
  }

  try {
    const upstreamClaim = await requestJson("/v1/invitations/pending/process", {
      method: "POST",
      headers: {
        authorization,
      },
      body: {
        treeId,
        personId,
      },
    });

    if (!upstreamClaim.ok) {
      sendJson(
        req,
        res,
        upstreamClaim.status,
        upstreamClaim.payload,
        {"x-rodnya-claim-shim": "1"},
      );
      return;
    }

    const mergeResult = await mergeDuplicatePersons({
      authorization,
      treeId,
      claimedPersonId: personId,
    });

    sendJson(
      req,
      res,
      200,
      {
        ...upstreamClaim.payload,
        person: withSyntheticIdentity(
          mergeResult.claimedPerson || upstreamClaim.payload?.person || null,
        ),
      },
      {
        [claimShimHeader]: "1",
        [identityShimHeader]: "1",
        "x-rodnya-claim-duplicates-merged": String(
          mergeResult.duplicatePersonIds.length,
        ),
      },
    );

    console.log(
      JSON.stringify({
        type: "claim-merged",
        treeId,
        personId,
        mergedDuplicatePersonIds: mergeResult.duplicatePersonIds,
        relationRewriteCount: mergeResult.relationRewriteCount,
      }),
    );
  } catch (error) {
    console.error("[claim-merge-shim] failed", error);
    sendJson(
      req,
      res,
      502,
      {
        message: "Не удалось завершить merge claim-flow",
        details: error instanceof Error ? error.message : String(error),
      },
      {
        [claimShimHeader]: "1",
        [identityShimHeader]: "1",
      },
    );
  }
}

function isShimmedRoute(url) {
  if (url === "/v1/invitations/pending/process") {
    return true;
  }

  if (/^\/v1\/relation-requests\/[^/]+\/respond$/.test(url || "")) {
    return true;
  }

  if (/^\/v1\/trees\/[^/]+\/persons$/.test(url || "")) {
    return true;
  }

  if (/^\/v1\/trees\/[^/]+\/persons\/[^/]+$/.test(url || "")) {
    return true;
  }

  return false;
}

const server = http.createServer((req, res) => {
  if (req.method === "OPTIONS" && isShimmedRoute(req.url || "")) {
    sendNoContent(req, res, {[identityShimHeader]: "1"});
    return;
  }

  if (req.url === "/v1/invitations/pending/process" && req.method === "POST") {
    void handleClaim(req, res);
    return;
  }

  if (/^\/v1\/relation-requests\/[^/]+\/respond$/.test(req.url || "")) {
    void proxyJsonEndpoint(req, res, {
      transformPayload(payload) {
        return {
          ...payload,
          person: withSyntheticIdentity(payload.person),
        };
      },
    });
    return;
  }

  if (/^\/v1\/trees\/[^/]+\/persons$/.test(req.url || "")) {
    void proxyJsonEndpoint(req, res, {
      transformPayload(payload) {
        if (!Array.isArray(payload?.persons)) {
          return payload;
        }
        return {
          ...payload,
          persons: payload.persons.map(withSyntheticIdentity),
        };
      },
    });
    return;
  }

  if (/^\/v1\/trees\/[^/]+\/persons\/[^/]+$/.test(req.url || "")) {
    void proxyJsonEndpoint(req, res, {
      transformPayload(payload) {
        return {
          ...payload,
          person: withSyntheticIdentity(payload.person),
        };
      },
    });
    return;
  }

  if (req.method === "GET" && req.url === "/ready") {
    sendJson(req, res, 200, {ok: true, service: "claim-merge-shim"});
    return;
  }

  sendJson(req, res, 404, {message: "Not found"});
});

server.listen(port, "127.0.0.1", () => {
  console.log(
    `[claim-merge-shim] listening on http://127.0.0.1:${port} -> ${upstreamBaseUrl}`,
  );
});
