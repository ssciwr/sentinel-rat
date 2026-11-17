"""Seed reference data for the Sentinel Rat database.

Run after the schema is created (see ``dashboard.init_db``). It is idempotent:
every routine checks for existing rows first, so it is safe to run on each
startup. Add new seed data by writing a ``seed_*`` routine and calling it from
``seed()``.

This script is executed by the ``db-init`` service, which runs the
``sentinel-rat-dashboard`` image, where the ``dashboard`` ORM package is installed.
"""

from __future__ import annotations

import logging

from dashboard.db import camera_crud, taxonomy_crud
from dashboard.db.data_model import Camera, Taxonomy
from dashboard.db.database import SessionLocal
from sqlalchemy import select
from sqlalchemy.orm import Session

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Cameras to ensure exist. ``location`` is a (longitude, latitude) tuple
# (PostGIS POINT order), matching dashboard.db.utils.normalize_location.
CAMERAS: list[dict] = [
    {
        "name": "hd-zoo-01",
        # Heidelberg Zoo: 49.4153 N, 8.6608 E
        "location": (8.6608, 49.4153),
        "description": "first camera in HD Zoo",
    },
]


def seed_cameras(session: Session) -> None:
    for cam in CAMERAS:
        existing = session.scalars(
            select(Camera).where(Camera.name == cam["name"])
        ).first()
        if existing is not None:
            logger.info(
                "Camera %s already exists (id=%s), skipping", cam["name"], existing.id
            )
            continue

        created = camera_crud.add(
            session,
            name=cam["name"],
            location=cam["location"],
            description=cam["description"],
        )
        logger.info("Seeded camera %s (id=%s)", created.name, created.id)


# Species to ensure exist. A species is identified by genus and species, like the
# pipeline does when it stores a classification, so the pipeline reuses these rows.
TAXONOMY: list[dict] = [
    {
        "kingdom": "Animalia",
        "phylum": "Chordata",
        "class_name": "Mammalia",
        "order": "Rodentia",
        "family": "Muridae",
        "genus": "Rattus",
        "species": "rattus",
        "common_name": "Black rat (also roof rat / house rat)",
        "is_predator": False,
    },
]


def seed_taxonomy(session: Session) -> None:
    for taxon in TAXONOMY:
        name = f"{taxon['genus']} {taxon['species']}"
        existing = session.scalars(
            select(Taxonomy).where(
                Taxonomy.genus == taxon["genus"],
                Taxonomy.species == taxon["species"],
            )
        ).first()
        if existing is None:
            created = taxonomy_crud.add(session, **taxon)
            logger.info("Seeded taxonomy %s (id=%s)", name, created.id)
            continue

        # the pipeline may have created the species already, from a classification
        # without e.g. is_predator: fill in the empty fields, keep the others
        filled = [
            field
            for field, value in taxon.items()
            if getattr(existing, field) is None and value is not None
        ]
        for field in filled:
            setattr(existing, field, taxon[field])
        if filled:
            session.commit()
            logger.info(
                "Taxonomy %s already exists (id=%s), filled in %s",
                name,
                existing.id,
                ", ".join(filled),
            )
        else:
            logger.info("Taxonomy %s already exists (id=%s), skipping", name, existing.id)


def seed() -> None:
    session = SessionLocal()
    try:
        seed_cameras(session)
        seed_taxonomy(session)
    finally:
        session.close()
    logger.info("Seeding complete")


if __name__ == "__main__":
    seed()
