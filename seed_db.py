"""Seed reference data for the Sentinel Rat database.

Run after the schema is created (see ``dashboard.init_db``). It is idempotent:
every routine checks for existing rows first, so it is safe to run on each
startup. Add new seed data by writing a ``seed_*`` routine and calling it from
``seed()``.

This script is executed by the ``db-init`` service, which runs the pipeline
image where the ``sentinel-rat-dashboard`` ORM package is installed.
"""

from __future__ import annotations

import logging

from dashboard.db import camera_crud
from dashboard.db.data_model import Camera
from dashboard.db.database import SessionLocal
from sqlalchemy import select
from sqlalchemy.orm import Session

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Cameras to ensure exist. ``location`` is a (longitude, latitude) tuple
# (PostGIS POINT order), matching dashboard.db.utils.normalize_location.
CAMERAS: list[dict] = [
    {
        "name": "HDCAM01",
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


def seed_taxonomy(session: Session) -> None:
    # TODO: add taxonomy seed data here.
    pass


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
