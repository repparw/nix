"""Run the claim-diff jq filter against fixture claimer databases."""

import json
import os
import subprocess
import unittest

DIFF = os.path.join(os.path.dirname(__file__), "claim-diff.jq")


def run_diff(epic, gog, previous):
    result = subprocess.run(
        [
            "jq",
            "-n",
            "--argjson",
            "epic",
            json.dumps(epic if epic is not None else {}),
            "--argjson",
            "gog",
            json.dumps(gog if gog is not None else {}),
            "--argjson",
            "previous",
            json.dumps(previous),
            "-f",
            DIFF,
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


class ClaimDiffTest(unittest.TestCase):
    def test_new_claim_is_reported(self):
        db = {
            "repparw": {
                "game-a": {
                    "title": "Game A",
                    "url": "https://store.epicgames.com/p/game-a",
                    "status": "claimed",
                },
            },
        }
        out = run_diff(db, {}, {})
        self.assertEqual(
            out["lines"],
            ["✅ epic: Game A — https://store.epicgames.com/p/game-a"],
        )
        self.assertEqual(out["state"], {"epic|repparw|game-a": "claimed"})

    def test_failed_claim_is_reported_with_status(self):
        db = {
            "repparw": {
                "game-b": {
                    "title": "Game B",
                    "url": "https://www.gog.com/en/game/game_b",
                    "status": "failed",
                },
            },
        }
        out = run_diff({}, db, {})
        self.assertEqual(
            out["lines"],
            ["⚠️ gog: Game B (failed) — https://www.gog.com/en/game/game_b"],
        )

    def test_known_statuses_are_not_reported(self):
        db = {
            "repparw": {
                "game-a": {
                    "title": "Game A",
                    "url": "https://store.epicgames.com/p/game-a",
                    "status": "existed",
                },
                "game-c": {
                    "title": "Game C",
                    "url": "https://store.epicgames.com/p/game-c",
                    "status": "manual",
                },
            },
        }
        out = run_diff(db, {}, {})
        self.assertEqual(out["lines"], [])
        self.assertEqual(out["state"], {})

    def test_status_transition_is_reported_once(self):
        failed = {"repparw": {"g1": {"title": "G", "url": "u", "status": "failed"}}}
        claimed = {"repparw": {"g1": {"title": "G", "url": "u", "status": "claimed"}}}
        state = run_diff(claimed, {}, {})["state"]

        again = run_diff(claimed, {}, state)
        self.assertEqual(again["lines"], [])

        first = run_diff(claimed, {}, {})
        self.assertEqual(first["lines"], ["✅ epic: G — u"])

        # the failed DB never notified because the state moved straight to
        # claimed; simulate the intermediate state explicitly instead
        mid = run_diff(failed, {}, {})
        self.assertEqual(mid["lines"], ["⚠️ epic: G (failed) — u"])
        transition = run_diff(claimed, {}, mid["state"])
        self.assertEqual(transition["lines"], ["✅ epic: G — u"])

    def test_missing_databases_are_empty(self):
        out = run_diff(None, None, {})
        self.assertEqual(out["lines"], [])
        self.assertEqual(out["state"], {})

    def test_malformed_user_entry_is_skipped(self):
        db = {"repparw": "not-an-object"}
        out = run_diff(db, {}, {})
        self.assertEqual(out["lines"], [])
        self.assertEqual(out["state"], {})


if __name__ == "__main__":
    unittest.main()
