from datetime import UTC, datetime, timedelta

from app.services.matching import cosine_similarity, date_similarity, score_candidate, tag_similarity


def test_similarity_helpers() -> None:
    assert cosine_similarity([1.0, 0.0], [1.0, 0.0]) == 1.0
    assert cosine_similarity([1.0, 0.0], [0.0, 1.0]) == 0.0
    assert tag_similarity(["рюкзак", "чёрный"], ["черный", "рюкзак"]) > 0.3
    now = datetime.now(UTC)
    assert date_similarity(now, now + timedelta(days=30)) == 0.0


def test_candidate_score_is_explainable() -> None:
    now = datetime.now(UTC)
    score, factors = score_candidate(
        source_tags=["рюкзак", "красная молния"],
        candidate_tags=["рюкзак", "красная молния"],
        source_date=now,
        candidate_date=now,
        distance=0.5,
        source_embedding=[1.0, 0.0],
        candidate_embedding=[0.99, 0.01],
        same_category=True,
    )
    assert score > 90
    assert set(factors) == {"visual", "tags", "date", "location", "category"}


def test_missing_photo_can_match_but_unrelated_photos_are_not_ignored() -> None:
    now = datetime.now(UTC)
    common = dict(source_tags=["чёрный", "красная молния"], candidate_tags=["Черный", "красная молния"],
                  source_date=now, candidate_date=now, distance=0, same_category=True)
    score, factors = score_candidate(**common, source_embedding=None, candidate_embedding=[1, 0])
    assert score >= 80 and "visual" not in factors
    score, factors = score_candidate(**common, source_embedding=[0, 1], candidate_embedding=[1, 0])
    assert score < 80 and factors["visual"] == 0
    common["candidate_tags"] = ["белый зонт"]
    score, _ = score_candidate(**common, source_embedding=None, candidate_embedding=None)
    assert score < 80  # Place, date and category alone cannot trigger a notification.
