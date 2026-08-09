#!/usr/bin/env python3
"""Create Protein+ subscriptions, trials, localizations, and Vitals PPP prices."""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib

BUNDLE = "com.jackwallner.protein"
# App Store Connect reference names are internal and immutable after creation.
# User-facing group and product names come from localized products.json files.
GROUP_REFERENCE_NAME = "Protein Plus"
SUBS = [
    ("com.jackwallner.protein.monthly", "Protein Plus Monthly", "ONE_MONTH", "1.99", "Monthly access to Protein+."),
    ("com.jackwallner.protein.yearly", "Protein Plus Yearly", "ONE_YEAR", "14.99", "Yearly access to Protein+."),
]
TIERS = {
    "IND": ("4.99", "0.69"), "PAK": ("4.99", "0.69"), "BGD": ("4.99", "0.69"), "IDN": ("4.99", "0.69"),
    "VNM": ("4.99", "0.69"), "PHL": ("4.99", "0.69"), "EGY": ("4.99", "0.69"), "NGA": ("4.99", "0.69"),
    "TUR": ("7.99", "0.99"), "BRA": ("7.99", "0.99"), "MEX": ("7.99", "0.99"), "COL": ("7.99", "0.99"),
    "CHL": ("7.99", "0.99"), "THA": ("7.99", "0.99"), "MYS": ("7.99", "0.99"), "POL": ("7.99", "0.99"),
    "HUN": ("7.99", "0.99"), "ROU": ("7.99", "0.99"), "ZAF": ("7.99", "0.99"), "RUS": ("7.99", "0.99"),
    "SAU": ("11.99", "1.49"), "ARE": ("11.99", "1.49"), "CZE": ("11.99", "1.49"), "CHN": ("11.99", "1.49"),
}
FX = {
    "IND": .012, "PAK": .0036, "BGD": .0082, "IDN": .000062, "VNM": .0000395, "PHL": .0173,
    "EGY": .020, "NGA": .00065, "TUR": .029, "BRA": .20, "MEX": .049, "COL": .00024,
    "CHL": .0011, "THA": .029, "MYS": .22, "POL": .25, "HUN": .0028, "ROU": .22,
    "ZAF": .055, "RUS": .011, "SAU": .27, "ARE": .27, "CZE": .044, "CHN": .14, "USA": 1.0,
}


def ensure_price(c: asc_lib.ASCClient, sub_id: str, territory: str, target: float) -> None:
    existing = asc_lib.list_all(c, f"/subscriptions/{sub_id}/prices?filter[territory]={territory}&limit=200")
    if territory == "USA" and existing:
        return
    points = asc_lib.list_all(c, f"/subscriptions/{sub_id}/pricePoints?filter[territory]={territory}&limit=200")
    if not points:
        print(f"no price points for {territory}, using Apple's equalized price")
        return
    ranked = sorted((float(p["attributes"]["customerPrice"]) * FX[territory], p) for p in points)
    eligible = [item for item in ranked if item[0] <= target]
    _, chosen = eligible[-1] if eligible else ranked[0]
    existing_points = {
        (item.get("relationships", {}).get("subscriptionPricePoint", {}).get("data") or {}).get("id")
        for item in existing if item.get("attributes", {}).get("manual")
    }
    if chosen["id"] in existing_points:
        return
    c.post("/subscriptionPrices", {"data": {"type": "subscriptionPrices", "relationships": {
        "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
        "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": chosen["id"]}},
    }}})


def main() -> None:
    c = asc_lib.ASCClient.from_credentials()
    app_id = asc_lib.find_app(c, BUNDLE)["id"]
    locales = json.loads((Path(__file__).parent / "asc-supported-locales.json").read_text())["locales"]
    territories = [t["id"] for t in asc_lib.list_all(c, "/territories?limit=200")]
    groups = asc_lib.list_all(c, f"/apps/{app_id}/subscriptionGroups")
    group = next((g for g in groups if g["attributes"]["referenceName"] == GROUP_REFERENCE_NAME), None)
    if not group:
        group = c.post("/subscriptionGroups", {"data": {"type": "subscriptionGroups", "attributes": {"referenceName": GROUP_REFERENCE_NAME}, "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
    group_id = group["id"]
    group_locs = {x["attributes"]["locale"]: x for x in asc_lib.list_all(c, f"/subscriptionGroups/{group_id}/subscriptionGroupLocalizations")}
    for locale in locales:
        product_path = asc_lib.META / locale / "products.json"
        product = json.loads(product_path.read_text()) if product_path.exists() else {}
        group_name = product.get("group") or GROUP_REFERENCE_NAME
        if locale in group_locs:
            existing = group_locs[locale]
            if existing["attributes"].get("name") != group_name:
                c.patch(f"/subscriptionGroupLocalizations/{existing['id']}", {"data": {"type": "subscriptionGroupLocalizations", "id": existing["id"], "attributes": {"name": group_name}}})
        else:
            c.post("/subscriptionGroupLocalizations", {"data": {"type": "subscriptionGroupLocalizations", "attributes": {"locale": locale, "name": group_name}, "relationships": {"subscriptionGroup": {"data": {"type": "subscriptionGroups", "id": group_id}}}}})
    existing = {x["attributes"]["productId"]: x for x in asc_lib.list_all(c, f"/subscriptionGroups/{group_id}/subscriptions")}
    for index, (pid, name, period, price, description) in enumerate(SUBS):
        sub = existing.get(pid)
        if not sub:
            sub = c.post("/subscriptions", {"data": {"type": "subscriptions", "attributes": {"name": name, "productId": pid, "subscriptionPeriod": period, "familySharable": False, "groupLevel": 1, "reviewNote": "Unlocks Protein+: wrist logging, quick-add presets, reminders, and 30-day history."}, "relationships": {"group": {"data": {"type": "subscriptionGroups", "id": group_id}}}}})["data"]
        sid = sub["id"]
        locs = {x["attributes"]["locale"]: x for x in asc_lib.list_all(c, f"/subscriptions/{sid}/subscriptionLocalizations")}
        product_prefix = "monthly" if period == "ONE_MONTH" else "yearly"
        for locale in locales:
            product_path = asc_lib.META / locale / "products.json"
            product = json.loads(product_path.read_text()) if product_path.exists() else {}
            localized_name = product.get(f"{product_prefix}_name") or name
            localized_description = product.get(f"{product_prefix}_desc") or description
            if locale in locs:
                existing_loc = locs[locale]
                attrs = existing_loc["attributes"]
                if attrs.get("name") != localized_name or attrs.get("description") != localized_description:
                    c.patch(f"/subscriptionLocalizations/{existing_loc['id']}", {"data": {"type": "subscriptionLocalizations", "id": existing_loc["id"], "attributes": {"name": localized_name, "description": localized_description}}})
            else:
                c.post("/subscriptionLocalizations", {"data": {"type": "subscriptionLocalizations", "attributes": {"locale": locale, "name": localized_name, "description": localized_description}, "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}}}}})
        try:
            availability = c.get(f"/subscriptions/{sid}/subscriptionAvailability").get("data")
        except RuntimeError:
            availability = None
        if not availability:
            c.post("/subscriptionAvailabilities", {"data": {"type": "subscriptionAvailabilities", "attributes": {"availableInNewTerritories": True}, "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}}, "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]}}}})
        ensure_price(c, sid, "USA", float(price))
        offers = asc_lib.list_all(c, f"/subscriptions/{sid}/introductoryOffers?include=territory&limit=200")
        covered = {(x.get("relationships", {}).get("territory", {}).get("data") or {}).get("id") for x in offers}
        for territory in territories:
            if territory not in covered:
                c.post("/subscriptionIntroductoryOffers", {"data": {"type": "subscriptionIntroductoryOffers", "attributes": {"duration": "ONE_WEEK", "offerMode": "FREE_TRIAL", "numberOfPeriods": 1}, "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}}, "territory": {"data": {"type": "territories", "id": territory}}}}})
        for territory, targets in TIERS.items():
            ensure_price(c, sid, territory, float(targets[1 if period == "ONE_MONTH" else 0]))
        print(f"configured {pid} ({sid})")


if __name__ == "__main__":
    main()
