#!/usr/bin/env python3
"""Configure the nonlocalized Caffeine App Store listing fields."""
from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_lib as A  # noqa: E402


BUNDLE_ID = "com.jackwallner.caffeine"
APP_NAME = "Caffeine Tracker: Bedtime"
# Age-rating answers are copied from a live health app and then overridden
# below. This pointed at the retired Protein Tracker record, so the copy
# would start failing the moment that record went away.
AGE_TEMPLATE_BUNDLE_ID = os.environ.get(
    "ASC_AGE_TEMPLATE_BUNDLE_ID", "com.jackwallner.vitals"
)
REVIEW_NOTES = """Caffeine reads and writes the HealthKit dietaryCaffeine type only.

TO TEST WITHOUT HEALTH DATA: complete onboarding, open Now, and tap Preview a drink. Choose a milligram dose and time. The preview shows its estimated effect at bedtime before anything is saved. Tap Log to save it. The main screen then shows consumed today, estimated remaining now, and estimated remaining at bedtime.

HEALTH PERMISSIONS: onboarding requests read and write access for Dietary Caffeine in one sheet. If write access is declined, the app still works. Entries are stored locally until permission is available.

NO ACCOUNT IS REQUIRED. There is no login, ad network, food database, photo scanner, or server storing caffeine data.

LOGGING IS FREE. Logging on iPhone and Apple Watch, dose previews, the current estimate, the bedtime forecast, source controls, widgets, complications, and seven days of history work with no purchase. No reviewer action is needed to exercise the core feature.

CAFFEINE+ is an optional monthly or yearly subscription, each with a 7-day free trial for eligible customers, or a one-time lifetime purchase. It adds full history and trends, custom quick-preview amounts, and a bedtime estimate reminder.

All caffeine values are explicitly labeled estimates. The app does not measure caffeine in the bloodstream, provide a universal safe cutoff, diagnose, treat, cure, prevent, or prescribe. The bedtime amount is a user-selected preference, not a medical limit."""


def main() -> None:
    client = A.ASCClient.from_credentials()
    app = A.find_app(client, BUNDLE_ID)
    info = A.find_editable_app_info(client, app["id"])
    version = A.find_editable_version(client, app["id"])
    if not info or not version:
        raise SystemExit("error: Caffeine needs an editable app info and version")

    client.patch(
        f"/apps/{app['id']}",
        {
            "data": {
                "type": "apps",
                "id": app["id"],
                "attributes": {
                    "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT",
                },
            }
        },
    )
    client.patch(
        f"/appStoreVersions/{version['id']}",
        {
            "data": {
                "type": "appStoreVersions",
                "id": version["id"],
                "attributes": {
                    "copyright": "2026 Jack Wallner",
                    "releaseType": "MANUAL",
                },
            }
        },
    )
    age = client.get(f"/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    template_app = A.find_app(client, AGE_TEMPLATE_BUNDLE_ID)
    template_info = A.find_editable_app_info(client, template_app["id"])
    template_age = client.get(
        f"/appInfos/{template_info['id']}/ageRatingDeclaration"
    )["data"]["attributes"]
    attrs = {key: value for key, value in template_age.items() if value is not None}
    attrs.pop("ageRatingOverride", None)
    attrs.update(
        {
            "healthOrWellnessTopics": True,
            "medicalOrTreatmentInformation": "NONE",
            "alcoholTobaccoOrDrugUseOrReferences": "NONE",
        }
    )
    client.patch(
        f"/ageRatingDeclarations/{age['id']}",
        {
            "data": {
                "type": "ageRatingDeclarations",
                "id": age["id"],
                "attributes": attrs,
            }
        },
    )

    review = client.get(f"/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
    attributes = {
        "contactFirstName": "Jack",
        "contactLastName": "Wallner",
        "contactPhone": "14257533411",
        "contactEmail": "jackwallner@gmail.com",
        "demoAccountRequired": False,
        "notes": REVIEW_NOTES,
    }
    if review:
        client.patch(
            f"/appStoreReviewDetails/{review['id']}",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "id": review["id"],
                    "attributes": attributes,
                }
            },
        )
    else:
        client.post(
            "/appStoreReviewDetails",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": attributes,
                    "relationships": {
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version["id"]}
                        }
                    },
                }
            },
        )
    print(f"configured {APP_NAME} ({app['id']})")


if __name__ == "__main__":
    main()
