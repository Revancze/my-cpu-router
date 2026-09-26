from __future__ import annotations

import dataclasses
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.codelaxy import (
    SCHEMA_VERSION,
    Change,
    ContractError,
    Evidence,
    Requirement,
    Snapshot,
    Verdict,
    decode_record,
    encode_record,
)


FINGERPRINT_A = "sha256:" + "a" * 64
FINGERPRINT_B = "sha256:" + "b" * 64


class ToolingContractsTest(unittest.TestCase):
    def records(
        self,
    ) -> tuple[Snapshot, Requirement, Evidence, Verdict]:
        return (
            Snapshot(
                snapshot_id="snapshot-1",
                scope="staged",
                head_oid="0123456789abcdef",
                index_fingerprint=FINGERPRINT_A,
                worktree_fingerprint=None,
                changes=(
                    Change(
                        path="router.cpp",
                        kind="ordinary",
                        index_status="M",
                        worktree_status=".",
                    ),
                    Change(
                        path="router.hpp",
                        kind="ordinary",
                        index_status="M",
                        worktree_status=".",
                    ),
                ),
            ),
            Requirement(
                snapshot_id="snapshot-1",
                requirement_id="cpu-router-tests",
                kind="test",
            ),
            Evidence(
                snapshot_id="snapshot-1",
                producer="ironman",
                status="pass",
                input_fingerprint=FINGERPRINT_B,
                executed=(
                    "build:router.o",
                    "test:router_test",
                ),
                reused=(),
                started_at="2026-09-13T12:00:00Z",
                finished_at="2026-09-13T12:00:02Z",
            ),
            Verdict(
                snapshot_id="snapshot-1",
                ready=True,
                reasons=(),
                required_evidence=("ironman",),
            ),
        )

    def test_all_records_round_trip_through_deterministic_json(self) -> None:
        for record in self.records():
            with self.subTest(record=type(record).__name__):
                serialized = encode_record(record)
                self.assertTrue(serialized.endswith("\n"))
                self.assertEqual(decode_record(serialized), record)
                self.assertEqual(
                    encode_record(decode_record(serialized)),
                    serialized,
                )

    def test_records_are_immutable(self) -> None:
        snapshot = self.records()[0]

        with self.assertRaises(dataclasses.FrozenInstanceError):
            snapshot.scope = "worktree"  # type: ignore[misc]

        with self.assertRaisesRegex(ContractError, "immutable tuple"):
            Snapshot(
                snapshot_id="snapshot-1",
                scope="staged",
                head_oid=None,
                index_fingerprint=FINGERPRINT_A,
                worktree_fingerprint=None,
                changes=[  # type: ignore[arg-type]
                    Change(
                        path="router.cpp",
                        kind="ordinary",
                        index_status="M",
                        worktree_status=".",
                    )
                ],
            )

    def test_snapshot_exposes_changed_paths_without_losing_change_state(
        self,
    ) -> None:
        snapshot = self.records()[0]

        self.assertEqual(
            snapshot.changed_files,
            ("router.cpp", "router.hpp"),
        )
        self.assertEqual(snapshot.changes[0].index_status, "M")

    def test_rename_requires_its_original_path(self) -> None:
        with self.assertRaisesRegex(ContractError, "original path"):
            Change(
                path="renamed.cpp",
                kind="rename",
                index_status="R",
                worktree_status=".",
            )

    def test_untracked_change_requires_question_mark_status(self) -> None:
        with self.assertRaisesRegex(
            ContractError,
            r"must use \?\? status",
        ):
            Change(
                path="new.txt",
                kind="untracked",
                index_status=".",
                worktree_status="M",
            )

    def test_invalid_schema_version_is_rejected(self) -> None:
        payload = self.records()[0].to_dict()

        for version in (1, 2, 999):
            with self.subTest(version=version):
                payload["schema_version"] = version

                with self.assertRaisesRegex(
                    ContractError,
                    "unsupported schema version",
                ):
                    Snapshot.from_dict(payload)

        self.assertEqual(SCHEMA_VERSION, 3)

    def test_unknown_fields_are_rejected(self) -> None:
        payload = self.records()[1].to_dict()
        payload["surprise"] = True

        with self.assertRaisesRegex(
            ContractError,
            "unexpected",
        ):
            Requirement.from_dict(payload)

    def test_requirement_rejects_provider_execution_details(self) -> None:
        payload = self.records()[1].to_dict()
        payload["build_targets"] = ["router_test"]

        with self.assertRaisesRegex(
            ContractError,
            "unexpected",
        ):
            Requirement.from_dict(payload)

    def test_invalid_fingerprint_is_rejected(self) -> None:
        with self.assertRaisesRegex(
            ContractError,
            "sha256 fingerprint",
        ):
            Evidence(
                snapshot_id="snapshot-1",
                producer="ironman",
                status="pass",
                input_fingerprint="yesterday",
                executed=(),
                reused=(),
            )

    def test_ready_verdict_cannot_contain_blocking_reasons(self) -> None:
        with self.assertRaisesRegex(
            ContractError,
            "blocking reasons",
        ):
            Verdict(
                snapshot_id="snapshot-1",
                ready=True,
                reasons=("tests missing",),
                required_evidence=("ironman",),
            )

    def test_unknown_record_type_is_rejected(self) -> None:
        with self.assertRaisesRegex(
            ContractError,
            "unknown record type",
        ):
            decode_record('{"record_type":"telepath"}')

    def test_legacy_record_types_are_rejected(self) -> None:
        for record_type in ("plan", "receipt"):
            with self.subTest(record_type=record_type):
                with self.assertRaisesRegex(
                    ContractError,
                    "unknown record type",
                ):
                    decode_record(
                        f'{{"record_type":"{record_type}"}}'
                    )


if __name__ == "__main__":
    unittest.main()
