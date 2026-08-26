#!/usr/bin/env python3
"""Maintain Localizable.xcstrings.

Adds or updates entries for all three shipped languages — en (source), de, and
frk (Oberfraenkisch) — and clears the `stale` marker from keys that are in use
again. Written as a script so the catalog can be regenerated rather than
hand-edited, and so the translations are reviewable in one place.

Run from the repository root:

    python3 scripts/update_localizations.py

Idempotent: existing translations are only overwritten when this file supplies a
different value for the same key.
"""

from __future__ import annotations

import json
import pathlib
import sys

CATALOG = pathlib.Path("Localizable.xcstrings")

# key -> (de, frk)
TRANSLATIONS: dict[str, tuple[str, str]] = {
    # ---- Annual report (in-app labels; the generated PDF stays German) ----
    "Balance Sheet Data (as of 31 December)": (
        "Bilanzdaten (Stichtag 31.12.)", "Bilanzdatn (Stichtag 31.12.)"),
    "Income Statement %@": ("Erfolgsrechnung %@", "Erfolgsrechnung %@"),
    "Liquid assets (bank/cash) in CHF": (
        "Flüssige Mittel (Bank/Kasse) in CHF", "Flüssige Mittel (Bank/Kass) in CHF"),
    "Liabilities (debts) in CHF": (
        "Fremdkapital (Schulden) in CHF", "Fremdkapital (Schuldn) in CHF"),

    # ---- Asset classes (never extracted, so always showed in English) ----
    "IT & Computer": ("IT & Computer", "IT & Computer"),
    "Camera & Production Gear": (
        "Kamera- & Produktionsausrüstung", "Kamera- & Produktionszeich"),
    "Vehicles": ("Fahrzeuge", "Fahrzeuch"),
    "Office Furniture": ("Büromobiliar", "Büromöbl"),
    "Custom Rate": ("Eigener Satz", "Eichner Satz"),
    "Purchase Price": ("Kaufpreis", "Kaufpreis"),

    # ---- Previously missing everyday strings ----
    "Uncategorized": ("Ohne Kategorie", "Ohne Kategorie"),
    "N/A": ("k. A.", "k. A."),
    "PDF Document": ("PDF-Dokument", "PDF-Dokument"),
    "Edit Transaction": ("Eintrag bearbeiten", "Eintrach bearbeitn"),
    "Update": ("Aktualisieren", "Aktualisiern"),
    "Duplicate": ("Duplizieren", "Dupliziern"),

    # ---- Format strings that had no translation ----
    "%@ • %.1f%%": ("%@ • %.1f%%", "%@ • %.1f%%"),
    "(%@ %@)": ("(%@ %@)", "(%@ %@)"),
    "01.01.%@ – 31.12.%@": ("01.01.%@ – 31.12.%@", "01.01.%@ – 31.12.%@"),

    # ---- Error and confirmation titles ----
    "Could Not Save": ("Konnte nicht gespeichert werden", "Hods ned gspeichert"),
    "Could Not Delete": ("Konnte nicht gelöscht werden", "Hods ned glöscht"),
    "Could Not Rename": ("Konnte nicht umbenannt werden", "Hods ned umbenannt"),
    "Invoice": ("Rechnung", "Rechnung"),

    # ---- Transactions ----
    "Nothing Matches These Filters": (
        "Keine Treffer für diese Filter", "Nix gfundn mit den Filtern"),
    "No transactions in this year, type or category. "
    "Try a different fiscal year or clear the filters.": (
        "Keine Einträge in diesem Jahr, Typ oder dieser Kategorie. "
        "Wähle ein anderes Geschäftsjahr oder setze die Filter zurück.",
        "Kane Einträch in dem Johr, Typ oder der Kategorie. "
        "Nimm a anders Gschäftsjohr oder mach die Filter weg."),
    "Use the ‘+’ button to add your first income or expense entry for this year.": (
        "Nutze den ‘+’ Knopf, um den ersten Eintrag für dieses Jahr zu erstellen.",
        "Nimm den ‘+’ Knopf für dein erschtn Eintrach in dem Johr."),
    "Transaction Deleted": ("Eintrag gelöscht", "Eintrach glöscht"),
    "Pick another entry from the list.": (
        "Wähle einen anderen Eintrag aus der Liste.",
        "Nimm an andern Eintrach aus der Listn."),
    "Use this title and fill in its usual type, category and currency": (
        "Diesen Titel übernehmen und Typ, Kategorie und Währung wie üblich ausfüllen",
        "Den Titl nehma und Typ, Kategorie und Währung wie üblich neidou"),

    # ---- Invoices ----
    "Edit Invoice": ("Rechnung bearbeiten", "Rechnung bearbeitn"),
    "Duplicate as New Invoice": (
        "Als neue Rechnung duplizieren", "Als neue Rechnung dupliziern"),
    "Editable": ("Bearbeitbar", "Bearbeitbar"),
    "PDF only": ("Nur PDF", "Nur PDF"),
    "Save Changes": ("Änderungen speichern", "Änderunga speichern"),
    "Page %d of %d": ("Seite %d von %d", "Seitn %d vo %d"),
    "Remove this line": ("Diese Position entfernen", "Die Postn wegmacha"),
    "Reopen this invoice and change it": (
        "Diese Rechnung erneut öffnen und ändern",
        "Die Rechnung nochmal aufmacha und ändern"),
    "The PDF could not be created. Please try again.": (
        "Das PDF konnte nicht erstellt werden. Bitte versuche es erneut.",
        "Des PDF hods ned hikriecht. Probier's nochmal."),
    "This invoice was saved before editing was supported, so its details are not "
    "stored. Use \"Duplicate as New Invoice\" to re-enter them once.": (
        "Diese Rechnung wurde gespeichert, bevor Bearbeiten möglich war; ihre Details "
        "sind nicht hinterlegt. Nutze „Als neue Rechnung duplizieren“, um sie einmal "
        "neu zu erfassen.",
        "Die Rechnung is gspeichert wordn, bevors Bearbeitn ganga is – d'Details sinn "
        "ned hinterlegt. Nimm „Als neue Rechnung dupliziern“ und gib's amol neu ei."),

    # ---- Database recovery ----
    "Your data could not be opened": (
        "Deine Daten konnten nicht geöffnet werden", "Deine Datn hods ned aufmachn könna"),
    "Try Again": ("Erneut versuchen", "Nochmal probiern"),
    "Back Up My Data and Start Fresh": (
        "Daten sichern und neu beginnen", "Datn sichern und neu anfanga"),
    "Show Backup in Finder": ("Sicherung im Finder zeigen", "Sicherung im Finder zeing"),
    "Your previous database was kept as a backup.": (
        "Deine bisherige Datenbank wurde als Sicherung behalten.",
        "Dei alte Datnbank is als Sicherung dablieebn."),
    "Your existing database is renamed, never deleted. You can send it to support "
    "or restore it later.": (
        "Deine bestehende Datenbank wird umbenannt, nie gelöscht. Du kannst sie "
        "später wiederherstellen oder einsenden.",
        "Dei bestehende Datnbank wird bloß umbenannt, nie glöscht. Du konnst se "
        "später widda hulln."),
    "The database was created by a version of MangoAccounting that this version "
    "cannot read. Quitting and reopening sometimes clears this. Nothing has been "
    "changed on disk.": (
        "Die Datenbank wurde mit einer Version von MangoAccounting erstellt, die "
        "diese Version nicht lesen kann. Ein Neustart hilft manchmal. Auf der "
        "Festplatte wurde nichts verändert.",
        "D'Datnbank is mit ana Version vo MangoAccounting gmacht wordn, die die do "
        "ned lesn konn. A Neustart hilft manchmal. Auf der Plattn is nix verändert wordn."),
    "The database file could not be read. This is often temporary — a full disk, a "
    "file still in use, or missing permissions. Nothing has been changed on disk.": (
        "Die Datenbankdatei konnte nicht gelesen werden. Das ist oft vorübergehend – "
        "volle Festplatte, Datei noch in Benutzung oder fehlende Rechte. Auf der "
        "Festplatte wurde nichts verändert.",
        "D'Datnbankdatei hods ned lesn könna. Des is oft bloß vorübergehend – volle "
        "Plattn, Datei nu in Benutzung oder fehlende Rechte. Auf der Plattn is nix "
        "verändert wordn."),
    "The database is available again.": (
        "Die Datenbank ist wieder verfügbar.", "D'Datnbank is widda do."),

    # The generated annual report is a Swiss statutory document and stays in
    # German in every language. Stated explicitly so it reads as a decision
    # rather than an untranslated key falling back to its own text.
    "BILANZ": ("BILANZ", "BILANZ"),
}

# Keys whose English originals are in use again; the German literals that had
# replaced them are gone.
REVIVE = [
    "Revenue", "Total Revenue", "Expenses", "Total Expenses",
    "Annual Profit", "Annual Loss",
    # Marked stale but still referenced by the source.
    "Bill Photo", "Timeframe",
]

# Keys no longer referenced anywhere in the source. Verified with a repo-wide
# search before listing here.
REMOVE = [
    "Purchase Price (CHF)",
    "Driver's Log",
    "Generiert durch MangoAccounting",
    "Note: Swiss ESTV generally allows 40% Degressive or 20% Linear for IT & Camera Equipment.",
    "Tap the ‘+’ button to add your first income or expense entry.",
    "from January 1 to December 31, %@",
    "vom 1. Januar bis 31. Dezember %@",
    "Flussige Mittel (Bank/Kasse) in CHF",   # typo'd key, replaced by an English one
    "Fremdkapital (Schulden) in CHF",
    "Balance Sheet Data (Stichtag 31.12.)",
    "Ertrag",                                 # in-app label, now "Revenue"
    "Aufwand",                                # in-app label, now "Expenses"
    "",                                       # empty key from a Picker("") label
]


def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def main() -> int:
    if not CATALOG.exists():
        print(f"error: {CATALOG} not found — run from the repository root", file=sys.stderr)
        return 1

    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog["strings"]
    added = updated = revived = removed = 0

    for key, (de, frk) in TRANSLATIONS.items():
        entry = strings.setdefault(key, {})
        if not entry:
            added += 1
        entry.pop("extractionState", None)
        locs = entry.setdefault("localizations", {})
        for lang, value in (("de", de), ("frk", frk)):
            existing = locs.get(lang, {}).get("stringUnit", {}).get("value")
            if existing != value:
                if existing is not None:
                    updated += 1
                locs[lang] = unit(value)

    for key in REVIVE:
        entry = strings.get(key)
        if entry and entry.pop("extractionState", None):
            revived += 1

    for key in REMOVE:
        if strings.pop(key, None) is not None:
            removed += 1

    catalog["strings"] = dict(sorted(strings.items()))
    CATALOG.write_text(
        json.dumps(catalog, indent=2, ensure_ascii=False, sort_keys=False) + "\n",
        encoding="utf-8",
    )

    print(f"added {added}, updated {updated}, revived {revived}, removed {removed}")
    print(f"catalog now holds {len(catalog['strings'])} keys")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
