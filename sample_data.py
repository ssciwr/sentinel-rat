"""Load optional SAMPLE / DEMO data into the Sentinel Rat database.

This is illustrative data to make the dashboard show something during a demo —
it is NOT required for the system to run and must never be loaded into a real
deployment. It is run on demand via the ``demo`` Compose profile:

    docker compose --profile demo up load-sample-data

It depends on the schema and seed data (cameras, taxonomy) already existing, so
it is run after ``db-init`` completes. Like the seed script it is idempotent:
each routine checks for existing rows first.

Add more demo rows by writing a ``load_*`` routine and calling it from
``load_sample_data()``.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from dashboard.db import camera_crud, image_crud
from dashboard.db.data_model import Camera, ImageCapture
from dashboard.db.database import SessionLocal
from sqlalchemy import select
from sqlalchemy.orm import Session

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Sample image captures, keyed by the camera they belong to (by name).
# ``captured_at`` is timezone-aware; ``image_path`` must be unique; ``location``
# is a (longitude, latitude) tuple (typically the camera's own location).
SAMPLE_IMAGES: list[dict] = [
    {
        "camera_name": "HDCAM01",
        "image_path": "HDCAM01_20260730_115638.jpg",
        "location": (8.6608, 49.4153),
        "captured_at": datetime(2026, 7, 30, 11, 56, 38, tzinfo=timezone.utc),
    },
]


def _camera_by_name(session: Session, name: str) -> Camera | None:
    return session.scalars(select(Camera).where(Camera.name == name)).first()


def load_sample_images(session: Session) -> None:
    for img in SAMPLE_IMAGES:
        existing = session.scalars(
            select(ImageCapture).where(ImageCapture.image_path == img["image_path"])
        ).first()
        if existing is not None:
            logger.info(
                "Image %s already exists (id=%s), skipping",
                img["image_path"],
                existing.id,
            )
            continue

        camera = _camera_by_name(session, img["camera_name"])
        if camera is None:
            logger.warning(
                "Camera %s not found (is it seeded?), skipping image %s",
                img["camera_name"],
                img["image_path"],
            )
            continue

        created = image_crud.add(
            session,
            camera_id=camera.id,
            image_path=img["image_path"],
            location=img["location"],
            captured_at=img["captured_at"],
        )
        logger.info("Loaded sample image %s (id=%s)", created.image_path, created.id)


def load_sample_detections(session: Session) -> None:
    # TODO: add sample object_detection / species_classification rows.
    # These need an ml_model row and taxonomy entries to exist first
    # (see seed_db.seed_taxonomy), so wire those up before enabling this.
    pass


def load_sample_data() -> None:
    session = SessionLocal()
    try:
        load_sample_images(session)
        load_sample_detections(session)
    finally:
        session.close()
    logger.info("Sample data loading complete")


if __name__ == "__main__":
    load_sample_data()
