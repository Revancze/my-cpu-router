"""JSON wire format for Codelaxy tooling records."""

from __future__ import annotations

import json
from typing import Mapping, TypeAlias

from .contracts import (
    ContractError,
    Evidence,
    Requirement,
    Snapshot,
    Verdict,
)


Record: TypeAlias = Snapshot | Requirement | Evidence | Verdict

RECORD_TYPES = {
    Snapshot.RECORD_TYPE: Snapshot,
    Requirement.RECORD_TYPE: Requirement,
    Evidence.RECORD_TYPE: Evidence,
    Verdict.RECORD_TYPE: Verdict,
}


def encode_record(record: Record) -> str:
    """Encode one record deterministically with a terminating newline."""

    return json.dumps(
        record.to_dict(),
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ) + "\n"


def decode_record(serialized: str) -> Record:
    """Decode and validate one record from the wire format."""

    try:
        payload = json.loads(serialized)
    except json.JSONDecodeError as error:
        raise ContractError(f"invalid JSON record: {error.msg}") from error

    if not isinstance(payload, Mapping):
        raise ContractError("record must be a JSON object")

    record_type = payload.get("record_type")
    if not isinstance(record_type, str):
        raise ContractError("record_type must be a string")
    record_class = RECORD_TYPES.get(record_type)
    if record_class is None:
        raise ContractError(f"unknown record type: {record_type!r}")

    return record_class.from_dict(payload)
