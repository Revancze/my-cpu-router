"""Versioned records exchanged by the Codelaxy Git tools."""

from __future__ import annotations

from dataclasses import dataclass
from typing import ClassVar, Mapping


SCHEMA_VERSION = 1
VALID_SCOPES = frozenset({"staged", "worktree"})
VALID_PRODUCERS = frozenset({"ironman", "mrproper"})
VALID_RECEIPT_STATUSES = frozenset({"fail", "pass"})


class ContractError(ValueError):
    """Raised when a tooling record violates its versioned contract."""


def _require_text(field_name: str, value: object) -> str:
    if not isinstance(value, str) or not value:
        raise ContractError(f"{field_name} must be a non-empty string")
    return value


def _optional_text(field_name: str, value: object) -> str | None:
    if value is None:
        return None
    return _require_text(field_name, value)


def _text_tuple(field_name: str, value: object) -> tuple[str, ...]:
    if not isinstance(value, tuple):
        raise ContractError(f"{field_name} must be an immutable tuple")

    result = tuple(_require_text(field_name, item) for item in value)
    if len(result) != len(set(result)):
        raise ContractError(f"{field_name} must not contain duplicates")
    return result


def _decoded_text_tuple(field_name: str, value: object) -> tuple[str, ...]:
    if not isinstance(value, list):
        raise ContractError(f"{field_name} must be a JSON array")
    return _text_tuple(field_name, tuple(value))


def _fingerprint(field_name: str, value: object) -> str:
    fingerprint = _require_text(field_name, value)
    prefix = "sha256:"
    digest = fingerprint.removeprefix(prefix)

    if not fingerprint.startswith(prefix) or len(digest) != 64:
        raise ContractError(f"{field_name} must be a sha256 fingerprint")

    if any(character not in "0123456789abcdef" for character in digest):
        raise ContractError(f"{field_name} must use lowercase hexadecimal")

    return fingerprint


def _schema_version(value: object) -> int:
    if value != SCHEMA_VERSION:
        raise ContractError(f"unsupported schema version: {value!r}")
    return SCHEMA_VERSION


def _record_payload(
    payload: Mapping[str, object],
    record_type: str,
    expected_fields: frozenset[str],
) -> dict[str, object]:
    if payload.get("record_type") != record_type:
        raise ContractError(f"expected record type {record_type!r}")

    actual_fields = frozenset(payload)
    if actual_fields != expected_fields:
        missing = sorted(expected_fields - actual_fields)
        unexpected = sorted(actual_fields - expected_fields)
        raise ContractError(
            f"invalid {record_type} fields; missing={missing}, "
            f"unexpected={unexpected}"
        )

    return dict(payload)


@dataclass(frozen=True, slots=True)
class Snapshot:
    """Immutable observation of one repository scope."""

    RECORD_TYPE: ClassVar[str] = "snapshot"

    snapshot_id: str
    scope: str
    head_oid: str | None
    index_fingerprint: str
    worktree_fingerprint: str | None
    changed_files: tuple[str, ...]
    schema_version: int = SCHEMA_VERSION

    def __post_init__(self) -> None:
        _schema_version(self.schema_version)
        _require_text("snapshot_id", self.snapshot_id)
        if self.scope not in VALID_SCOPES:
            raise ContractError(f"invalid snapshot scope: {self.scope!r}")
        _optional_text("head_oid", self.head_oid)
        _fingerprint("index_fingerprint", self.index_fingerprint)
        if self.worktree_fingerprint is not None:
            _fingerprint("worktree_fingerprint", self.worktree_fingerprint)
        _text_tuple("changed_files", self.changed_files)

    def to_dict(self) -> dict[str, object]:
        return {
            "record_type": self.RECORD_TYPE,
            "schema_version": self.schema_version,
            "snapshot_id": self.snapshot_id,
            "scope": self.scope,
            "head_oid": self.head_oid,
            "index_fingerprint": self.index_fingerprint,
            "worktree_fingerprint": self.worktree_fingerprint,
            "changed_files": list(self.changed_files),
        }

    @classmethod
    def from_dict(cls, payload: Mapping[str, object]) -> Snapshot:
        values = _record_payload(
            payload,
            cls.RECORD_TYPE,
            frozenset(
                {
                    "record_type",
                    "schema_version",
                    "snapshot_id",
                    "scope",
                    "head_oid",
                    "index_fingerprint",
                    "worktree_fingerprint",
                    "changed_files",
                }
            ),
        )
        return cls(
            schema_version=_schema_version(values["schema_version"]),
            snapshot_id=_require_text("snapshot_id", values["snapshot_id"]),
            scope=_require_text("scope", values["scope"]),
            head_oid=_optional_text("head_oid", values["head_oid"]),
            index_fingerprint=_fingerprint(
                "index_fingerprint", values["index_fingerprint"]
            ),
            worktree_fingerprint=(
                None
                if values["worktree_fingerprint"] is None
                else _fingerprint(
                    "worktree_fingerprint", values["worktree_fingerprint"]
                )
            ),
            changed_files=_decoded_text_tuple(
                "changed_files", values["changed_files"]
            ),
        )


@dataclass(frozen=True, slots=True)
class Plan:
    """Required work for one exact snapshot."""

    RECORD_TYPE: ClassVar[str] = "plan"

    snapshot_id: str
    cleanup_files: tuple[str, ...]
    build_targets: tuple[str, ...]
    tests: tuple[str, ...]
    fallback_reason: str | None = None
    schema_version: int = SCHEMA_VERSION

    def __post_init__(self) -> None:
        _schema_version(self.schema_version)
        _require_text("snapshot_id", self.snapshot_id)
        _text_tuple("cleanup_files", self.cleanup_files)
        _text_tuple("build_targets", self.build_targets)
        _text_tuple("tests", self.tests)
        _optional_text("fallback_reason", self.fallback_reason)

    def to_dict(self) -> dict[str, object]:
        return {
            "record_type": self.RECORD_TYPE,
            "schema_version": self.schema_version,
            "snapshot_id": self.snapshot_id,
            "cleanup_files": list(self.cleanup_files),
            "build_targets": list(self.build_targets),
            "tests": list(self.tests),
            "fallback_reason": self.fallback_reason,
        }

    @classmethod
    def from_dict(cls, payload: Mapping[str, object]) -> Plan:
        values = _record_payload(
            payload,
            cls.RECORD_TYPE,
            frozenset(
                {
                    "record_type",
                    "schema_version",
                    "snapshot_id",
                    "cleanup_files",
                    "build_targets",
                    "tests",
                    "fallback_reason",
                }
            ),
        )
        return cls(
            schema_version=_schema_version(values["schema_version"]),
            snapshot_id=_require_text("snapshot_id", values["snapshot_id"]),
            cleanup_files=_decoded_text_tuple(
                "cleanup_files", values["cleanup_files"]
            ),
            build_targets=_decoded_text_tuple(
                "build_targets", values["build_targets"]
            ),
            tests=_decoded_text_tuple("tests", values["tests"]),
            fallback_reason=_optional_text(
                "fallback_reason", values["fallback_reason"]
            ),
        )


@dataclass(frozen=True, slots=True)
class Receipt:
    """Evidence published by the tool that performed work."""

    RECORD_TYPE: ClassVar[str] = "receipt"

    snapshot_id: str
    producer: str
    status: str
    input_fingerprint: str
    executed: tuple[str, ...]
    reused: tuple[str, ...]
    started_at: str | None = None
    finished_at: str | None = None
    schema_version: int = SCHEMA_VERSION

    def __post_init__(self) -> None:
        _schema_version(self.schema_version)
        _require_text("snapshot_id", self.snapshot_id)
        if self.producer not in VALID_PRODUCERS:
            raise ContractError(f"invalid receipt producer: {self.producer!r}")
        if self.status not in VALID_RECEIPT_STATUSES:
            raise ContractError(f"invalid receipt status: {self.status!r}")
        _fingerprint("input_fingerprint", self.input_fingerprint)
        _text_tuple("executed", self.executed)
        _text_tuple("reused", self.reused)
        _optional_text("started_at", self.started_at)
        _optional_text("finished_at", self.finished_at)

    def to_dict(self) -> dict[str, object]:
        return {
            "record_type": self.RECORD_TYPE,
            "schema_version": self.schema_version,
            "snapshot_id": self.snapshot_id,
            "producer": self.producer,
            "status": self.status,
            "input_fingerprint": self.input_fingerprint,
            "executed": list(self.executed),
            "reused": list(self.reused),
            "started_at": self.started_at,
            "finished_at": self.finished_at,
        }

    @classmethod
    def from_dict(cls, payload: Mapping[str, object]) -> Receipt:
        values = _record_payload(
            payload,
            cls.RECORD_TYPE,
            frozenset(
                {
                    "record_type",
                    "schema_version",
                    "snapshot_id",
                    "producer",
                    "status",
                    "input_fingerprint",
                    "executed",
                    "reused",
                    "started_at",
                    "finished_at",
                }
            ),
        )
        return cls(
            schema_version=_schema_version(values["schema_version"]),
            snapshot_id=_require_text("snapshot_id", values["snapshot_id"]),
            producer=_require_text("producer", values["producer"]),
            status=_require_text("status", values["status"]),
            input_fingerprint=_fingerprint(
                "input_fingerprint", values["input_fingerprint"]
            ),
            executed=_decoded_text_tuple("executed", values["executed"]),
            reused=_decoded_text_tuple("reused", values["reused"]),
            started_at=_optional_text("started_at", values["started_at"]),
            finished_at=_optional_text("finished_at", values["finished_at"]),
        )


@dataclass(frozen=True, slots=True)
class Verdict:
    """Commit-readiness decision for one exact staged snapshot."""

    RECORD_TYPE: ClassVar[str] = "verdict"

    snapshot_id: str
    ready: bool
    reasons: tuple[str, ...]
    required_receipts: tuple[str, ...]
    schema_version: int = SCHEMA_VERSION

    def __post_init__(self) -> None:
        _schema_version(self.schema_version)
        _require_text("snapshot_id", self.snapshot_id)
        if not isinstance(self.ready, bool):
            raise ContractError("ready must be a boolean")
        _text_tuple("reasons", self.reasons)
        _text_tuple("required_receipts", self.required_receipts)
        if self.ready and self.reasons:
            raise ContractError("a ready verdict must not contain blocking reasons")

    def to_dict(self) -> dict[str, object]:
        return {
            "record_type": self.RECORD_TYPE,
            "schema_version": self.schema_version,
            "snapshot_id": self.snapshot_id,
            "ready": self.ready,
            "reasons": list(self.reasons),
            "required_receipts": list(self.required_receipts),
        }

    @classmethod
    def from_dict(cls, payload: Mapping[str, object]) -> Verdict:
        values = _record_payload(
            payload,
            cls.RECORD_TYPE,
            frozenset(
                {
                    "record_type",
                    "schema_version",
                    "snapshot_id",
                    "ready",
                    "reasons",
                    "required_receipts",
                }
            ),
        )
        ready = values["ready"]
        if not isinstance(ready, bool):
            raise ContractError("ready must be a boolean")
        return cls(
            schema_version=_schema_version(values["schema_version"]),
            snapshot_id=_require_text("snapshot_id", values["snapshot_id"]),
            ready=ready,
            reasons=_decoded_text_tuple("reasons", values["reasons"]),
            required_receipts=_decoded_text_tuple(
                "required_receipts", values["required_receipts"]
            ),
        )
