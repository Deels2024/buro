"use client";

export default function ErrorPage({ reset }: { error: Error; reset: () => void }) {
  return <main className="login-shell"><section className="login-card" role="alert">
    <h1>Не удалось открыть раздел</h1>
    <p>Попробуйте загрузить кабинет ещё раз. Если вы редактировали запись, проверьте сохранённые изменения.</p>
    <button className="primary-button" onClick={reset}>Открыть кабинет снова</button>
  </section></main>;
}
