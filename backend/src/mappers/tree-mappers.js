const {
  normalizePublicUrl,
  normalizePublicUrlList,
} = require("../profile-utils");
const {resolveUserDisplayName} = require("./notification-safety-mappers");

function mapProfileNote(note) {
  return {
    id: note.id,
    title: note.title,
    content: note.content,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
  };
}

function mapTree(tree) {
  return {
    id: tree.id,
    name: tree.name,
    description: tree.description,
    creatorId: tree.creatorId,
    memberIds: Array.isArray(tree.memberIds) ? tree.memberIds : [],
    members: Array.isArray(tree.members) ? tree.members : [],
    createdAt: tree.createdAt,
    updatedAt: tree.updatedAt,
    isPrivate: tree.isPrivate !== false,
    kind: tree.kind === "friends" ? "friends" : "family",
    publicSlug: tree.publicSlug || null,
    isCertified: tree.isCertified === true,
    certificationNote: tree.certificationNote || null,
    semyaId: tree.semyaId || null,
  };
}

function mapPerson(person) {
  const familySummary =
    person.familySummary || person.notes || person.bio || null;
  return {
    id: person.id,
    treeId: person.treeId,
    userId: person.userId,
    identityId: person.identityId || null,
    name: person.name,
    maidenName: person.maidenName,
    photoUrl: normalizePublicUrl(person.photoUrl),
    primaryPhotoUrl: normalizePublicUrl(
      person.primaryPhotoUrl || person.photoUrl || null,
    ),
    photoGallery: Array.isArray(person.photoGallery)
      ? person.photoGallery.map((entry) => ({
          id: entry.id,
          url: normalizePublicUrl(entry.url),
          thumbnailUrl: normalizePublicUrl(entry.thumbnailUrl || null),
          type: entry.type || "image",
          contentType: entry.contentType || null,
          caption: entry.caption || null,
          createdAt: entry.createdAt || null,
          updatedAt: entry.updatedAt || null,
          isPrimary: entry.isPrimary === true,
        }))
      : [],
    gender: person.gender,
    birthDate: person.birthDate,
    // F5: «знаю только год» — клиент по флагу прячет фейковое 1 января.
    birthDatePrecision: person.birthDatePrecision || "exact",
    birthPlace: person.birthPlace,
    deathDate: person.deathDate,
    deathDatePrecision: person.deathDatePrecision || "exact",
    deathPlace: person.deathPlace,
    familySummary,
    bio: familySummary,
    isAlive: person.isAlive !== false,
    visibility: person.visibility || (person.isAlive === false ? "tree" : "private"),
    creatorId: person.creatorId,
    createdAt: person.createdAt,
    updatedAt: person.updatedAt,
    notes: familySummary,
    details: person.details || null,
  };
}

function mapProfileContribution(contribution) {
  const fields =
    contribution?.fields && typeof contribution.fields === "object"
      ? contribution.fields
      : {};
  return {
    id: contribution.id,
    treeId: contribution.treeId,
    personId: contribution.personId,
    targetUserId: contribution.targetUserId,
    authorUserId: contribution.authorUserId || null,
    authorDisplayName: contribution.authorDisplayName || null,
    authorPhotoUrl: normalizePublicUrl(contribution.authorPhotoUrl || null),
    message: contribution.message || null,
    fields,
    status: contribution.status || "pending",
    createdAt: contribution.createdAt || null,
    updatedAt: contribution.updatedAt || null,
    respondedAt: contribution.respondedAt || null,
    responderUserId: contribution.responderUserId || null,
  };
}

function mapRelation(relation) {
  return {
    id: relation.id,
    treeId: relation.treeId,
    person1Id: relation.person1Id,
    person2Id: relation.person2Id,
    relation1to2: relation.relation1to2,
    relation2to1: relation.relation2to1,
    isConfirmed: relation.isConfirmed === true,
    createdAt: relation.createdAt,
    updatedAt: relation.updatedAt,
    createdBy: relation.createdBy,
    marriageDate: relation.marriageDate || null,
    divorceDate: relation.divorceDate || null,
    customRelationLabel1to2: relation.customRelationLabel1to2 || null,
    customRelationLabel2to1: relation.customRelationLabel2to1 || null,
    parentSetId: relation.parentSetId || null,
    parentSetType: relation.parentSetType || null,
    isPrimaryParentSet:
      typeof relation.isPrimaryParentSet === "boolean"
        ? relation.isPrimaryParentSet
        : null,
    unionId: relation.unionId || null,
    unionType: relation.unionType || null,
    unionStatus: relation.unionStatus || null,
  };
}

function mapTreeGraphSnapshot(snapshot) {
  return {
    treeId: snapshot.treeId,
    viewerPersonId: snapshot.viewerPersonId || null,
    people: Array.isArray(snapshot.people) ? snapshot.people.map(mapPerson) : [],
    relations: Array.isArray(snapshot.relations)
      ? snapshot.relations.map(mapRelation)
      : [],
    familyUnits: Array.isArray(snapshot.familyUnits)
      ? snapshot.familyUnits.map((unit) => ({
          id: unit.id,
          rootParentSetId: unit.rootParentSetId || null,
          adultIds: Array.isArray(unit.adultIds) ? unit.adultIds : [],
          childIds: Array.isArray(unit.childIds) ? unit.childIds : [],
          relationIds: Array.isArray(unit.relationIds) ? unit.relationIds : [],
          unionId: unit.unionId || null,
          unionType: unit.unionType || null,
          unionStatus: unit.unionStatus || null,
          parentSetType: unit.parentSetType || null,
          isPrimaryParentSet: unit.isPrimaryParentSet === true,
          label: unit.label || "Семья",
        }))
      : [],
    viewerDescriptors: Array.isArray(snapshot.viewerDescriptors)
      ? snapshot.viewerDescriptors.map((descriptor) => ({
          personId: descriptor.personId,
          primaryRelationLabel: descriptor.primaryRelationLabel || null,
          isBlood: descriptor.isBlood === true,
          alternatePathCount: Number(descriptor.alternatePathCount || 0),
          pathSummary: descriptor.pathSummary || null,
          primaryPathPersonIds: Array.isArray(descriptor.primaryPathPersonIds)
            ? descriptor.primaryPathPersonIds
            : [],
        }))
      : [],
    branchBlocks: Array.isArray(snapshot.branchBlocks)
      ? snapshot.branchBlocks.map((branchBlock) => ({
          id: branchBlock.id,
          rootUnitId: branchBlock.rootUnitId,
          label: branchBlock.label || "Семья",
          memberPersonIds: Array.isArray(branchBlock.memberPersonIds)
            ? branchBlock.memberPersonIds
            : [],
        }))
      : [],
    generationRows: Array.isArray(snapshot.generationRows)
      ? snapshot.generationRows.map((row) => ({
          row: Number(row.row || 0),
          label: row.label || null,
          personIds: Array.isArray(row.personIds) ? row.personIds : [],
          familyUnitIds: Array.isArray(row.familyUnitIds) ? row.familyUnitIds : [],
        }))
      : [],
    warnings: Array.isArray(snapshot.warnings)
      ? snapshot.warnings.map((warning) => ({
          id: warning.id,
          code: warning.code || "graph_warning",
          severity: warning.severity || "warning",
          message: warning.message || "Дерево требует проверки.",
          hint: warning.hint || null,
          personIds: Array.isArray(warning.personIds) ? warning.personIds : [],
          familyUnitIds: Array.isArray(warning.familyUnitIds)
            ? warning.familyUnitIds
            : [],
          relationIds: Array.isArray(warning.relationIds) ? warning.relationIds : [],
        }))
      : [],
  };
}

function mapTreeChangeRecord(record, context = {}) {
  const details =
    record.details && typeof record.details === "object"
      ? record.details
      : {};
  const resolvedPersonName =
    context.personName ||
    record.personName ||
    details?.after?.name ||
    details?.before?.name ||
    null;
  const resolvedActorName = context.actorName || record.actorName || null;
  return {
    id: record.id,
    treeId: record.treeId,
    actorId: record.actorId || null,
    actorName: resolvedActorName,
    type: record.type,
    personId: record.personId || null,
    personName: resolvedPersonName,
    personIds: Array.isArray(record.personIds) ? record.personIds : [],
    relationId: record.relationId || null,
    mediaId: record.mediaId || null,
    createdAt: record.createdAt,
    details,
  };
}

function mapRelationRequest(request) {
  return {
    id: request.id,
    treeId: request.treeId,
    senderId: request.senderId,
    recipientId: request.recipientId,
    senderToRecipient: request.senderToRecipient,
    relationType: request.senderToRecipient,
    targetPersonId: request.targetPersonId || request.offlineRelativeId || null,
    offlineRelativeId:
      request.offlineRelativeId || request.targetPersonId || null,
    createdAt: request.createdAt,
    updatedAt: request.updatedAt,
    respondedAt: request.respondedAt || null,
    status: request.status || "pending",
    message: request.message || null,
  };
}

function mapTreeInvitation(invitation, tree = null) {
  return {
    invitationId: invitation.id,
    treeId: invitation.treeId,
    userId: invitation.userId,
    role: invitation.role || "pending",
    addedAt: invitation.addedAt,
    addedBy: invitation.addedBy || null,
    acceptedAt: invitation.acceptedAt || null,
    relationToTree: invitation.relationToTree || null,
    tree: tree ? mapTree(tree) : null,
    invitedBy: invitation.addedBy || null,
  };
}


module.exports = {
  mapProfileNote,
  mapTree,
  mapPerson,
  mapProfileContribution,
  mapRelation,
  mapTreeGraphSnapshot,
  mapTreeChangeRecord,
  mapRelationRequest,
  mapTreeInvitation,
};
