#!/usr/bin/env python3
"""Report what the App Store Connect record still needs before submission.

Read-only. Run it before a submission pass to see the gaps rather than
discovering them in the ASC web UI one blocked field at a time.

    python3 scripts/asc-readiness.py

Note on paths: `asc_lib.API` already ends in `/v1`, so every path passed to the
client must start at the resource (`/builds`, not `/v1/builds`).

Two things this script cannot see, because Apple does not expose them in the
App Store Connect API at all:

  * the **Regulated Medical Device** declaration (App Review 1.4.1), which is
    web-UI only. Protein Tracker answers No: it tracks a number the user or
    their clinician set and makes no diagnostic or treatment claim.
  * whether the privacy/support/marketing URLs actually resolve. This script
    fetches them, because App Review rejects on a dead privacy URL and the
    fleet convention of serving them from the repo's own GitHub Pages means
    they 404 until that repo exists and is public.
"""
from __future__ import annotations

import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_lib as A  # noqa: E402

BUNDLE_ID = "com.jackwallner.protein"
EXPECTED_NAME = "Protein Tracker - Grams Today"
EXPECTED_CATEGORY = "HEALTH_AND_FITNESS"
EXPECTED_SCREENSHOTS_BY_TYPE = {
    "APP_IPHONE_67": 5,
    "APP_WATCH_SERIES_10": 5,
}
EXPECTED_INTRO_OFFERS = 175

ready: list[str] = []
gaps: list[str] = []


def check(label: str, value, good: bool | None = None) -> None:
    good = bool(value) if good is None else good
    (ready if good else gaps).append(f"{label}: {value}")


def url_status(url: str) -> str:
    try:
        request = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(request, timeout=20) as response:
            return str(response.status)
    except urllib.error.HTTPError as error:
        return str(error.code)
    except Exception as error:  # noqa: BLE001 - any network failure is a gap
        return type(error).__name__


def main() -> None:
    client = A.ASCClient.from_credentials()
    app = A.find_app(client, BUNDLE_ID)
    info = A.find_editable_app_info(client, app["id"])
    version = A.find_editable_version(client, app["id"])

    name = app["attributes"].get("name")
    check("app record name", name, name == EXPECTED_NAME)

    category = client.get(f"/appInfos/{info['id']}/primaryCategory").get("data")
    check(
        "primary category",
        category and category["id"],
        bool(category) and category["id"] == EXPECTED_CATEGORY,
    )
    copyright_text = version["attributes"].get("copyright")
    check("copyright", copyright_text)

    urls: list[str] = []
    for localization in A.list_all(client, f"/appInfos/{info['id']}/appInfoLocalizations"):
        attributes = localization["attributes"]
        localized_name = attributes.get("name") or ""
        subtitle = attributes.get("subtitle") or ""
        check("name", f"{len(localized_name)} chars", 24 <= len(localized_name) <= 30)
        check("subtitle", f"{len(subtitle)} chars", 24 <= len(subtitle) <= 30)
        privacy = attributes.get("privacyPolicyUrl")
        check("privacy url", privacy)
        if privacy:
            urls.append(privacy)

    for localization in A.list_all(
        client, f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations"
    ):
        attributes = localization["attributes"]
        description = attributes.get("description") or ""
        keywords = attributes.get("keywords") or ""
        check("description", f"{len(description)} chars", len(description) > 200)
        check("description has no hardcoded price", "clean", not re.search(r"[$€£]\s*\d", description))
        disclosure_terms = (
            "renews automatically",
            "24 hours",
            "Privacy Policy",
            "Terms of Use",
        )
        check(
            "subscription disclosure",
            "complete" if all(term in description for term in disclosure_terms) else "incomplete",
            all(term in description for term in disclosure_terms),
        )
        check("keywords", f"{len(keywords)} chars", 94 <= len(keywords) <= 100)
        for field in ("supportUrl", "marketingUrl"):
            value = attributes.get(field)
            check(field, value)
            if value:
                urls.append(value)
        for screenshot_set in A.list_all(
            client, f"/appStoreVersionLocalizations/{localization['id']}/appScreenshotSets"
        ):
            images = A.list_all(
                client, f"/appScreenshotSets/{screenshot_set['id']}/appScreenshots"
            )
            display_type = screenshot_set["attributes"].get("screenshotDisplayType")
            # A fastlane retry can double-upload, so assert the exact count
            # rather than merely "some screenshots exist".
            expected_screenshots = EXPECTED_SCREENSHOTS_BY_TYPE.get(display_type, 4)
            check(
                f"screenshots {display_type}",
                len(images),
                len(images) == expected_screenshots,
            )

    declaration = client.get(f"/appInfos/{info['id']}/ageRatingDeclaration")["data"]["attributes"]
    check(
        "age rating",
        f"wellness={declaration.get('healthOrWellnessTopics')} "
        f"medical={declaration.get('medicalOrTreatmentInformation')}",
        declaration.get("healthOrWellnessTopics") is True,
    )

    review_detail = client.get(
        f"/appStoreVersions/{version['id']}/appStoreReviewDetail"
    ).get("data")
    check("review detail", "present" if review_detail else None)
    if review_detail:
        review_attributes = review_detail["attributes"]
        for field in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail"):
            check(f"review {field}", "present" if review_attributes.get(field) else None)
        review_notes = review_attributes.get("notes") or ""
        check(
            "review notes describe free logging",
            "current" if "LOGGING IS FREE" in review_notes else "stale",
            "LOGGING IS FREE" in review_notes,
        )

    # Paid-product review notes sit beside the app review notes in Apple's
    # queue. They must describe the same free/paid split as the binary.
    groups = A.list_all(client, f"/apps/{app['id']}/subscriptionGroups")
    for group in groups:
        for subscription in A.list_all(client, f"/subscriptionGroups/{group['id']}/subscriptions"):
            attributes = subscription["attributes"]
            product_id = attributes.get("productId") or subscription["id"]
            check(
                f"subscription {product_id}",
                attributes.get("state"),
                attributes.get("state") == "READY_TO_SUBMIT",
            )
            note = attributes.get("reviewNote") or ""
            stale_terms = ("wrist logging", "30-day history", "30 day history")
            check(
                f"subscription note {product_id}",
                "current" if note and not any(term in note.lower() for term in stale_terms) else "stale",
                bool(note) and not any(term in note.lower() for term in stale_terms),
            )
            offers = A.list_all(
                client,
                f"/subscriptions/{subscription['id']}/introductoryOffers?limit=200",
            )
            check(
                f"subscription trial territories {product_id}",
                len(offers),
                len(offers) == EXPECTED_INTRO_OFFERS,
            )

    for purchase in A.list_all(client, f"/apps/{app['id']}/inAppPurchasesV2"):
        attributes = purchase["attributes"]
        product_id = attributes.get("productId") or purchase["id"]
        check(
            f"in-app purchase {product_id}",
            attributes.get("state"),
            attributes.get("state") == "READY_TO_SUBMIT",
        )

    # Which build, not just whether one is attached. A draft version keeps
    # whatever build was attached first, so an app that has uploaded ten more
    # since then still reports "a build is attached" while pointing at a binary
    # that predates the product. Build 8 sat on the 1.0 draft for two days
    # after logging went free, so the description promised a free tap the
    # attached binary charged for.
    build = client.get(f"/appStoreVersions/{version['id']}/build").get("data")
    attached_version = build["attributes"].get("version") if build else None
    check("attached build", attached_version)
    if attached_version:
        newest = max(
            (
                b["attributes"]["version"]
                for b in A.list_all(client, f"/builds?filter[app]={app['id']}&limit=200")
                if b["attributes"].get("processingState") == "VALID"
                and not b["attributes"].get("expired")
            ),
            key=lambda v: int(v) if v.isdigit() else -1,
            default=None,
        )
        check(
            "attached build is the newest VALID build",
            f"attached {attached_version}, newest {newest}",
            attached_version == newest,
        )

    print("READY:")
    for line in ready:
        print("  +", line)
    print("\nGAPS:")
    for line in gaps:
        print("  -", line)
    if not gaps:
        print("  (none)")

    print("\nURL REACHABILITY (App Review rejects on a dead privacy URL):")
    for url in dict.fromkeys(urls):
        status = url_status(url)
        marker = "+" if status == "200" else "-"
        print(f"  {marker} {status}  {url}")

    print("\nNOT VISIBLE TO THE API, CHECK BY HAND IN APP STORE CONNECT:")
    print("  * Regulated Medical Device declaration -> answer No")
    print("  * RevenueCat 'default' offering must have 3 packages "
          "(scripts/rc-setup.py)")


if __name__ == "__main__":
    main()
