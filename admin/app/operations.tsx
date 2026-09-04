"use client";
import { FormEvent, useEffect, useRef, useState } from "react";
import Image from "next/image";

type Media = { id: string; download_url: string; mime_type: string; status: string };
type Listing = { id: string; title: string; description: string; public_region: string; category: string; status: string; moderation_status: string; media: Media[]; storage_code?: string };
type Review = { claim: { id: string; status: string; decision_reason?: string }; listing: Listing; answers: Record<string, string>; hidden_features: string[]; evidence: { id: string; note: string; evidence_type: string; status: string; media: Media | null }[] };
type Message = { id: string; body: string; internal: boolean; created_at: string };
const categories: Record<string, string> = { bags:"Сумки и рюкзаки", documents:"Документы", keys:"Ключи", electronics:"Электроника", clothing:"Одежда", jewelry:"Украшения", pets:"Животные", toys:"Игрушки", sport:"Спорт", other:"Другое" };
async function api<T>(path: string, method = "GET", body?: unknown): Promise<T> {
  const r = await fetch("/api/backend" + path, { method, cache:"no-store", headers: body ? {"Content-Type":"application/json"} : undefined, body: body ? JSON.stringify(body) : undefined });
  const data = await r.json();
  if (!r.ok) throw new Error(typeof data.detail === "string" ? data.detail : "Проверьте заполнение полей");
  return data as T;
}
export function MediaGallery({media}:{media:Media[]}) {
  return <div className="evidence-gallery">{media.map(m=><figure key={m.id}>{m.mime_type.startsWith("image/") ? <a href={m.download_url} target="_blank" rel="noreferrer"><Image src={m.download_url} width={360} height={240} unoptimized alt="Фотография вещи или доказательство" style={{objectFit:"contain",width:"100%",height:220}} /></a> : <a href={m.download_url} target="_blank" rel="noreferrer">Открыть файл</a>}<figcaption>{m.status === "ready" ? "Проверено" : m.status === "processing" ? "Файл проверяется" : "Файл отклонён"}</figcaption></figure>)}</div>;
}

export function OperationalDrawer({id,kind,onClose,onChanged}:{id:string;kind:"listing"|"claim"|"ticket";onClose:()=>void;onChanged:()=>void}) {
  const dialog=useRef<HTMLDialogElement>(null);
  const [listing,setListing]=useState<Listing|null>(null), [review,setReview]=useState<Review|null>(null);
  const [messages,setMessages]=useState<Message[]>([]), [text,setText]=useState(""), [error,setError]=useState(""), [notice,setNotice]=useState(""), [busy,setBusy]=useState(false), [loading,setLoading]=useState(true);
  useEffect(()=>{dialog.current?.showModal();},[]);
  useEffect(()=>{
    let active=true;
    async function load(){
      try{
        if(kind==="listing"){const r=await api<Listing>(`/listings/${id}/manage`);if(active)setListing(r);}
        if(kind==="claim"){const r=await api<Review>(`/claims/${id}/review`);if(active)setReview(r);}
        if(kind==="ticket"){const r=await api<Message[]>(`/support/tickets/${id}/messages`);if(active)setMessages(r);}
      }catch(e){if(active)setError((e as Error).message);}finally{if(active)setLoading(false);}
    }
    void load();return()=>{active=false;};
  },[id,kind]);
  async function run(action:()=>Promise<void>){setBusy(true);setError("");setNotice("");try{await action();onChanged();}catch(e){setError((e as Error).message);}finally{setBusy(false);}}
  async function upload(files:FileList|null){
    if(!files||!listing)return;
    await run(async()=>{
      const media=[...listing.media];
      for(const file of Array.from(files).slice(0,9-media.length)){
        if(!["image/jpeg","image/png","image/webp"].includes(file.type))throw new Error("Поддерживаются JPEG, PNG и WebP");
        const signed=await api<{object_key:string;upload_url:string;required_headers:Record<string,string>}>("/media/presign","POST",{filename:file.name,mime_type:file.type,size_bytes:file.size,purpose:"listing"});
        const bytes=await file.arrayBuffer();
        const digest=await crypto.subtle.digest("SHA-256",bytes);
        const sha256=Array.from(new Uint8Array(digest),x=>x.toString(16).padStart(2,"0")).join("");
        const uploaded=await fetch(signed.upload_url,{method:"PUT",headers:signed.required_headers,body:bytes});
        if(!uploaded.ok)throw new Error("Не удалось загрузить фотографию");
        media.push(await api<Media>("/media/complete","POST",{object_key:signed.object_key,mime_type:file.type,size_bytes:file.size,sha256,purpose:"listing"}));
        setListing({...listing,media:[...media]});
      }
      setNotice("Фото загружены. Сохраните изменения карточки.");
    });
  }
  async function save(status:string){if(!listing)return;await run(async()=>{const updated=await api<Listing>(`/listings/${id}`,"PATCH",{title:listing.title,description:listing.description,category:listing.category,storage_code:listing.storage_code,media_ids:listing.media.map(m=>m.id),status});setListing(updated);setNotice(status==="active"?"Карточка отправлена на модерацию":"Черновик сохранён");});}
  async function decide(decision:string){await run(async()=>{if(text.trim().length<3)throw new Error("Укажите причину решения или вопрос заявителю");await api(`/claims/${id}/decision`,"POST",{decision,reason:text.trim()});setReview(await api<Review>(`/claims/${id}/review`));setNotice("Решение сохранено");});}
  async function send(e:FormEvent){e.preventDefault();await run(async()=>{await api(`/support/tickets/${id}/messages`,"POST",{body:text,internal:false,attachment_ids:[]});setText("");setMessages(await api<Message[]>(`/support/tickets/${id}/messages`));setNotice("Ответ отправлен");});}
  return <dialog ref={dialog} className="operational-dialog" onCancel={onClose} aria-label={kind==="claim"?"Проверка владельца":kind==="listing"?"Публикация":"Переписка поддержки"}>
    <div className="drawer-head"><h2>{kind==="claim"?"Проверка владельца":kind==="listing"?"Публикация":"Поддержка"}</h2><button autoFocus onClick={onClose} aria-label="Закрыть">×</button></div>
    {error&&<p role="alert" className="form-error">{error}</p>}{notice&&<p role="status">{notice}</p>}{loading&&<p>Загружаем…</p>}
    {listing&&<div className="operation-form"><MediaGallery media={listing.media}/><div>{listing.media.map((m,i)=><button className="filter-button" key={m.id} onClick={()=>setListing({...listing,media:listing.media.filter(x=>x.id!==m.id)})}>Убрать фото {i+1}</button>)}</div><label>Добавить фотографии<input type="file" accept="image/jpeg,image/png,image/webp" multiple disabled={busy} onChange={e=>void upload(e.target.files)}/></label><label>Название<input value={listing.title} onChange={e=>setListing({...listing,title:e.target.value})} maxLength={180}/></label><label>Описание<textarea value={listing.description} onChange={e=>setListing({...listing,description:e.target.value})} maxLength={5000}/></label><label>Категория<select value={listing.category} onChange={e=>setListing({...listing,category:e.target.value})}>{Object.entries(categories).map(([code,title])=><option key={code} value={code}>{title}</option>)}</select></label><p>Место: {listing.public_region}</p><label>Код хранения<input value={listing.storage_code??""} onChange={e=>setListing({...listing,storage_code:e.target.value})}/></label><p>Статус: {listing.status} · Модерация: {listing.moderation_status}</p><div className="modal-actions"><button disabled={busy} className="filter-button" onClick={()=>void save("draft")}>Сохранить черновик</button><button disabled={busy} className="primary-button" onClick={()=>void save("active")}>На модерацию</button></div></div>}
    {review&&<section className="operation-form"><h3>{review.listing.title}</h3><p>{review.listing.description}</p><MediaGallery media={review.listing.media}/><h3>Скрытые признаки находки</h3><p>{review.hidden_features.join(", ")||"Не указаны"}</p><h3>Ответы заявителя</h3>{Object.entries(review.answers).map(([q,a])=><p key={q}><strong>{q}</strong><br/>{a}</p>)}<h3>Доказательства</h3>{review.evidence.length===0&&<p>Файлы не приложены. Сравните ответы или запросите уточнение.</p>}{review.evidence.map(e=><article key={e.id}><p>{e.evidence_type} · {e.note}</p>{e.media?<MediaGallery media={[e.media]}/>:<p>Файл пока недоступен: {e.status}</p>}</article>)}<p>Статус: {review.claim.status}. {review.claim.decision_reason}</p>{["under_review","needs_more_info"].includes(review.claim.status)&&<><label>Обоснование решения<textarea value={text} onChange={e=>setText(e.target.value)} maxLength={2000}/></label><div className="modal-actions"><button disabled={busy} className="danger-button" onClick={()=>void decide("rejected")}>Отклонить</button><button disabled={busy} className="filter-button" onClick={()=>void decide("needs_more_info")}>Запросить уточнение</button><button disabled={busy} className="primary-button" onClick={()=>void decide("approved")}>Подтвердить</button></div></>}</section>}
    {kind==="ticket"&&!loading&&<section className="operation-form"><div className="support-messages">{messages.map(m=><article key={m.id}><small>{new Date(m.created_at).toLocaleString("ru-RU")}{m.internal?" · Внутренняя заметка":""}</small><p>{m.body}</p></article>)}</div><form onSubmit={send}><label>Ответ пользователю<textarea value={text} onChange={e=>setText(e.target.value)} minLength={1} maxLength={4000} required/></label><div className="modal-actions"><button className="primary-button" disabled={busy}>Отправить ответ</button><button type="button" className="filter-button" disabled={busy} onClick={()=>void run(async()=>{await api(`/admin/support/tickets/${id}`,"PATCH",{status:"resolved"});setNotice("Обращение решено");})}>Отметить решённым</button></div></form></section>}
  </dialog>;
}

export function TrafficCounts(){
  const [data,setData]=useState<{counts:Record<string,number>}|null>(null),[error,setError]=useState("");
  useEffect(()=>{api<{counts:Record<string,number>}>("/admin/analytics/traffic").then(setData).catch(e=>setError(e.message));},[]);
  const labels:Record<string,string>={home:"Открытия главной",search:"Просмотры каталога",listing_view:"Просмотры карточек",publication:"Новые публикации",claim_submitted:"Отправленные заявки",handover_completed:"Возвраты"};
  return <section className="panel"><h2>События за 30 дней</h2><p>Счётчики событий с момента установки. Без cookies и идентификаторов. Повторные просмотры и роботы учитываются; это не уникальные посетители и не когортная конверсия.</p>{error&&<p role="alert">{error}</p>}<div className="operations-grid">{data&&Object.entries(data.counts).map(([key,count])=><article key={key}><strong>{count}</strong><p>{labels[key]??key}</p></article>)}</div></section>;
}
