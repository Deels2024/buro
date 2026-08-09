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
