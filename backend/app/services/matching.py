import math
from collections.abc import Iterable
from datetime import datetime


def cosine_similarity(left: list[float] | None, right: list[float] | None) -> float:
    if not left or not right or len(left) != len(right):
        return 0.0
    dot = sum(a * b for a, b in zip(left, right, strict=True))
    left_norm = math.sqrt(sum(value * value for value in left))
    right_norm = math.sqrt(sum(value * value for value in right))
    if not left_norm or not right_norm:
        return 0.0
    return max(0.0, min(1.0, dot / (left_norm * right_norm)))


def tag_similarity(left: Iterable[str], right: Iterable[str]) -> float:
    left_set = {value.strip().lower() for value in left if value.strip()}
    right_set = {value.strip().lower() for value in right if value.strip()}
    union = left_set | right_set
    return len(left_set & right_set) / len(union) if union else 0.0


def date_similarity(left: datetime, right: datetime, horizon_days: int = 30) -> float:
    delta_days = abs((left - right).total_seconds()) / 86400
    return max(0.0, 1.0 - delta_days / horizon_days)


def distance_km(lat1: float | None, lon1: float | None, lat2: float | None, lon2: float | None) -> float | None:
    if None in (lat1, lon1, lat2, lon2):
        return None
    radius = 6371.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    value = math.sin(delta_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
    return radius * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value))


def location_similarity(distance: float | None, radius_km: float = 100.0) -> float:
    if distance is None:
        return 0.25
    return max(0.0, 1.0 - distance / radius_km)


def score_candidate(
    *,
    source_tags: list[str],
    candidate_tags: list[str],
    source_date: datetime,
    candidate_date: datetime,
    distance: float | None,
    source_embedding: list[float] | None,
    candidate_embedding: list[float] | None,
    same_category: bool,
) -> tuple[float, dict[str, float]]:
    factors = {
        "visual": cosine_similarity(source_embedding, candidate_embedding),
        "tags": tag_similarity(source_tags, candidate_tags),
        "date": date_similarity(source_date, candidate_date),
        "location": location_similarity(distance),
        "category": 1.0 if same_category else 0.25,
    }
    weights = {"visual": 0.45, "tags": 0.18, "date": 0.15, "location": 0.12, "category": 0.10}
    score = sum(factors[key] * weights[key] for key in weights)
    return round(score * 100, 2), {key: round(value * 100, 2) for key, value in factors.items()}
