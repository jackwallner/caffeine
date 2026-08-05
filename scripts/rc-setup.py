#!/usr/bin/env python3
"""Wire the Protein App Store products into RevenueCat.

This is the one step blocking a real purchase. The `default` offering exists in
the Protein RC project but has **zero packages**, so a device build shows
"Protein+ Plans Unavailable" no matter how healthy the App Store side is.

Usage:
    RC_KEY=sk_... python3 scripts/rc-setup.py            # apply
    RC_KEY=sk_... DRY_RUN=1 python3 scripts/rc-setup.py  # preview

The `sk_` secret key is a RevenueCat **management** key from Dashboard →
Project settings → API keys → Secret keys. It is deliberately not stored on
disk and must never ship in an app binary (App Review 1.4). Pass it in the
environment for this one run.

Ported from ~/health/scripts/rc-setup.py with one substantive difference: that
version indexes into the offering's existing packages and would raise a
KeyError here, because Protein's offering has none yet. This one creates any
missing package before attaching products to it.
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

BASE = "https://api.revenuecat.com/v2"
BUNDLE_ID = "com.jackwallner.protein"
PROJECT_NAMES = {"protein", "protein tracker", "protein tracker - grams left"}
ENTITLEMENT_KEY = "pro"
ENTITLEMENT_NAME = "Protein+"

# (store identifier, display name, RC product type, offering package key)
PRODUCTS = (
    ("com.jackwallner.protein.monthly", "Monthly", "subscription", "$rc_monthly"),
    ("com.jackwallner.protein.yearly", "Yearly", "subscription", "$rc_annual"),
    ("com.jackwallner.protein.pro.lifetime", "Lifetime", "one_time", "$rc_lifetime"),
)

DRY_RUN = os.environ.get("DRY_RUN") == "1"


def request(method: str, path: str, body: dict | None = None) -> dict:
    key = os.environ.get("RC_KEY")
    if not key:
        raise SystemExit(
            "error: set RC_KEY to a RevenueCat secret (sk_...) management key.\n"
            "       Dashboard -> Project settings -> API keys -> Secret keys."
        )
    if DRY_RUN and method != "GET":
        print(f"  [dry-run] {method} {path} {json.dumps(body) if body else ''}")
        return {"id": "dry-run", "items": []}

    req = urllib.request.Request(BASE + path, method=method)
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(req, data=data, timeout=120) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()[:800]
        raise RuntimeError(f"{method} {path} -> {error.code}: {detail}") from error


def find_project() -> dict:
    projects = request("GET", "/projects")["items"]
    for project in projects:
        if project["name"].strip().lower() in PROJECT_NAMES:
            return project
    names = ", ".join(repr(project["name"]) for project in projects)
    raise SystemExit(
        f"error: no RevenueCat project matching {sorted(PROJECT_NAMES)}.\n"
        f"       Projects on this account: {names}\n"
        f"       Add the right name to PROJECT_NAMES and re-run."
    )


def find_app(project_id: str) -> dict:
    apps = request("GET", f"/projects/{project_id}/apps")["items"]
    for app in apps:
        if app.get("app_store", {}).get("bundle_id") == BUNDLE_ID:
            return app
    raise SystemExit(
        f"error: no app in this project with bundle id {BUNDLE_ID}.\n"
        f"       Create the App Store app in RevenueCat first."
    )


def ensure_products(project_id: str, app_id: str) -> dict[str, dict]:
    existing = request("GET", f"/projects/{project_id}/products?limit=100")["items"]
    by_identifier = {product["store_identifier"]: product for product in existing}

    configured: dict[str, dict] = {}
    for identifier, display_name, product_type, _ in PRODUCTS:
        product = by_identifier.get(identifier)
        if product is None:
            product = request(
                "POST",
                f"/projects/{project_id}/products",
                {
                    "store_identifier": identifier,
                    "app_id": app_id,
                    "type": product_type,
                    "display_name": display_name,
                },
            )
            print(f"  created product  {identifier}")
        else:
            print(f"  product exists   {identifier}")
        configured[identifier] = product
    return configured


def ensure_entitlement(project_id: str) -> dict:
    entitlements = request("GET", f"/projects/{project_id}/entitlements")["items"]
    for entitlement in entitlements:
        if entitlement["lookup_key"] == ENTITLEMENT_KEY:
            print(f"  entitlement ok   {ENTITLEMENT_KEY}")
            return entitlement
    entitlement = request(
        "POST",
        f"/projects/{project_id}/entitlements",
        {"lookup_key": ENTITLEMENT_KEY, "display_name": ENTITLEMENT_NAME},
    )
    print(f"  created entitlement {ENTITLEMENT_KEY}")
    return entitlement


def attach_to_entitlement(project_id: str, entitlement: dict, products: dict[str, dict]) -> None:
    attached = request(
        "GET",
        f"/projects/{project_id}/entitlements/{entitlement['id']}/products?limit=100",
    )["items"]
    attached_ids = {product["id"] for product in attached}
    missing = [
        product["id"] for product in products.values() if product["id"] not in attached_ids
    ]
    if not missing:
        print(f"  entitlement has all {len(products)} products")
        return
    request(
        "POST",
        f"/projects/{project_id}/entitlements/{entitlement['id']}/actions/attach_products",
        {"product_ids": missing},
    )
    print(f"  attached {len(missing)} products to '{entitlement['lookup_key']}'")


def ensure_offering(project_id: str) -> dict:
    offerings = request("GET", f"/projects/{project_id}/offerings")["items"]
    for offering in offerings:
        if offering.get("lookup_key") == "default" or offering.get("is_current"):
            return offering
    offering = request(
        "POST",
        f"/projects/{project_id}/offerings",
        {"lookup_key": "default", "display_name": "Protein+", "is_current": True},
    )
    print("  created offering 'default'")
    return offering


def ensure_packages(project_id: str, offering: dict, products: dict[str, dict]) -> None:
    """Create the three packages if absent, then attach each product to its own.

    This is the step that is actually missing on this project: the offering is
    present and current but empty, which is exactly what makes the paywall show
    its unavailable state on a real device.
    """
    packages = request(
        "GET", f"/projects/{project_id}/offerings/{offering['id']}/packages?limit=100"
    )["items"]
    by_key = {package["lookup_key"]: package for package in packages}

    for identifier, display_name, _, package_key in PRODUCTS:
        package = by_key.get(package_key)
        if package is None:
            package = request(
                "POST",
                f"/projects/{project_id}/offerings/{offering['id']}/packages",
                {"lookup_key": package_key, "display_name": display_name},
            )
            print(f"  created package  {package_key}")
        else:
            print(f"  package exists   {package_key}")

        if package["id"] == "dry-run":
            print(f"  [dry-run] would attach {identifier} -> {package_key}")
            continue

        attached = request(
            "GET", f"/projects/{project_id}/packages/{package['id']}/products?limit=100"
        )["items"]
        attached_ids = {item["product"]["id"] for item in attached}
        product = products[identifier]
        if product["id"] in attached_ids:
            print(f"  already attached {identifier} -> {package_key}")
            continue
        request(
            "POST",
            f"/projects/{project_id}/packages/{package['id']}/actions/attach_products",
            {"products": [{"product_id": product["id"], "eligibility_criteria": "all"}]},
        )
        print(f"  attached         {identifier} -> {package_key}")


def verify(public_key: str) -> None:
    """Read the offering back through the public SDK endpoint, which is the
    exact call the app makes. Anything the app will see, this sees."""
    req = urllib.request.Request(
        "https://api.revenuecat.com/v1/subscribers/rc-setup-verify/offerings"
    )
    req.add_header("Authorization", f"Bearer {public_key}")
    req.add_header("X-Platform", "ios")
    with urllib.request.urlopen(req, timeout=60) as response:
        payload = json.loads(response.read())
    for offering in payload.get("offerings", []):
        count = len(offering.get("packages", []))
        state = "OK" if count else "STILL EMPTY"
        print(f"  offering '{offering['identifier']}': {count} packages [{state}]")


def main() -> None:
    project = find_project()
    project_id = project["id"]
    app = find_app(project_id)
    app_id = app["id"]
    print(f"project: {project['name']}")
    print(f"app:     {app['name']} ({BUNDLE_ID})")
    if DRY_RUN:
        print("mode:    DRY RUN, nothing will be written")

    print("\nproducts:")
    products = ensure_products(project_id, app_id)

    print("\nentitlement:")
    entitlement = ensure_entitlement(project_id)
    attach_to_entitlement(project_id, entitlement, products)

    print("\noffering packages:")
    offering = ensure_offering(project_id)
    ensure_packages(project_id, offering, products)

    keys = request("GET", f"/projects/{project_id}/apps/{app_id}/public_api_keys")["items"]
    production_key = next(
        (key["key"] for key in keys if key["environment"] == "production"), None
    )
    if production_key:
        print(f"\npublic SDK key: {production_key}")
        print("  (must match RevenueCatConfig.publicSDKKey in Shared/Services/StoreService.swift)")

    if not DRY_RUN and production_key:
        print("\nverifying through the public offerings endpoint the app uses:")
        verify(production_key)

    print("\ndone")


if __name__ == "__main__":
    main()
