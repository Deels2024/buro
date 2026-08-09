from app.db.models import Listing, MediaObject
from app.schemas import ListingOut, MediaOut
from app.services.storage import storage


def media_out(media: MediaObject) -> MediaOut:
    return MediaOut(
        id=media.id,
        mime_type=media.mime_type,
        size_bytes=media.size_bytes,
        status=media.status,
        download_url=storage.presign_download(media.object_key),
        width=media.width,
        height=media.height,
        duration_seconds=media.duration_seconds,
    )


def listing_out(listing: Listing) -> ListingOut:
    return ListingOut(
        id=listing.id,
        owner_id=listing.owner_id,
        organization_id=listing.organization_id,
        branch_id=listing.branch_id,
        kind=listing.kind,
        status=listing.status,
        title=listing.title,
        description=listing.description,
        category=listing.category,
        tags=listing.tags,
        public_features=listing.public_features,
        event_at=listing.event_at,
        public_region=listing.public_region,
        approx_latitude=listing.approx_latitude,
        approx_longitude=listing.approx_longitude,
        storage_code=listing.storage_code,
        ai_status=listing.ai_status,
        ai_confidence=listing.ai_confidence,
        moderation_status=listing.moderation_status,
        published_at=listing.published_at,
        media=[media_out(item) for item in listing.media if item.status != "blocked"],
        created_at=listing.created_at,
        updated_at=listing.updated_at,
    )
