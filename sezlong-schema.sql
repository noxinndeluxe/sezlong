-- =====================================================================
--  NOXINN DELUXE HOTEL – DİJİTAL ŞEZLONG YÖNETİM SİSTEMİ
--  Supabase şeması (Faz 1)
--  Kurulum: Supabase > SQL Editor > bu dosyanın tamamını yapıştır > Run
--  Dosya tekrar çalıştırılabilir (fonksiyonlar güncellenir, veri silinmez).
-- =====================================================================

-- ---------- TABLOLAR ----------

create table if not exists public.sz_ayarlar (
  id              int primary key default 1 check (id = 1),
  otel_adi        text not null default 'Noxinn Deluxe Hotel',
  bos_sure_dk     int  not null default 75 check (bos_sure_dk between 10 and 600),  -- "Buradayım" onayı gelmezse görevliye "kontrol et" önerisi
  uyari_sure_dk   int  not null default 30 check (uyari_sure_dk between 5 and 180), -- uyarı kartından sonra boşaltma için bekleme
  oda_basi_max    int  not null default 4  check (oda_basi_max between 1 and 20),
  oda_regex       text not null default '^[0-9]{3,4}$',
  kapanis_saati   time not null default '19:00',
  misafir_url     text not null default '',   -- sezlong.html adresi (QR'lar bu adrese yönlenir)
  guncellendi     timestamptz not null default now()
);
insert into public.sz_ayarlar (id) values (1) on conflict (id) do nothing;

create table if not exists public.sz_alanlar (
  id     serial primary key,
  kod    text not null unique check (kod ~ '^[A-Z0-9]{1,4}$'),
  ad     text not null,
  sira   int  not null default 0,
  aktif  boolean not null default true
);

create table if not exists public.sz_sezlonglar (
  id       serial primary key,
  alan_id  int  not null references public.sz_alanlar(id) on delete cascade,
  no       int  not null,
  kod      text not null unique,
  aktif    boolean not null default true,   -- false: sistemden çıkarıldı
  kapali   boolean not null default false,  -- true: geçici olarak kullanıma kapalı (bakım vb.)
  unique (alan_id, no)
);

create table if not exists public.sz_kullanimlar (
  id            bigserial primary key,
  sezlong_id    int  not null references public.sz_sezlonglar(id) on delete cascade,
  oda           text not null,
  basladi       timestamptz not null default now(),
  son_onay      timestamptz not null default now(),
  uyari_zamani  timestamptz,
  bitti         timestamptz,
  bitis_nedeni  text check (bitis_nedeni in ('misafir','gorevli','terk','gun_sonu')),
  gorevli_ile   boolean not null default false
);
create unique index if not exists kullanim_tek_acik on public.sz_kullanimlar (sezlong_id) where bitti is null;
create index if not exists kullanim_basladi on public.sz_kullanimlar (basladi);
create index if not exists kullanim_oda_acik on public.sz_kullanimlar (oda) where bitti is null;

create table if not exists public.sz_personel (
  user_id  uuid primary key references auth.users(id) on delete cascade,
  ad       text not null,
  rol      text not null check (rol in ('admin','gorevli'))
);

-- ---------- YARDIMCI FONKSİYONLAR ----------

create or replace function public.sz_bugun() returns date
language sql stable set search_path = '' as $$ select (now() at time zone 'Europe/Istanbul')::date $$;

create or replace function public.sz_oda(p text) returns text
language sql immutable set search_path = '' as $$ select upper(regexp_replace(coalesce(p,''), '\s', '', 'g')) $$;

create or replace function public.sz_personel_mi() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from sz_personel where user_id = auth.uid())
$$;

create or replace function public.sz_admin_mi() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from sz_personel where user_id = auth.uid() and rol = 'admin')
$$;

-- Önceki günlerden açık kalan kullanımları kapanış saatinde kapatır (gün sonu otomatik sıfırlama)
create or replace function public.sz_eski_kapat() returns void
language sql security definer set search_path = public as $$
  update sz_kullanimlar k
     set bitti = greatest(k.basladi,
                 (((k.basladi at time zone 'Europe/Istanbul')::date + a.kapanis_saati) at time zone 'Europe/Istanbul')),
         bitis_nedeni = 'gun_sonu'
    from sz_ayarlar a
   where a.id = 1 and k.bitti is null
     and (k.basladi at time zone 'Europe/Istanbul')::date < sz_bugun();
$$;

-- ---------- MİSAFİR FONKSİYONLARI (giriş gerektirmez) ----------

create or replace function public.misafir_sezlong(p_kod text, p_oda text default null) returns json
language plpgsql security definer set search_path = public as $$
declare s record; k record; a sz_ayarlar; v_benim boolean;
begin
  perform sz_eski_kapat();
  select * into a from sz_ayarlar where id = 1;
  select sz.id, sz.kod, sz.kapali, al.ad as alan_adi, al.id as alan_id into s
    from sz_sezlonglar sz join sz_alanlar al on al.id = sz.alan_id
   where sz.kod = upper(trim(p_kod)) and sz.aktif and al.aktif;
  if s.id is null then return json_build_object('ok', false, 'hata', 'bulunamadi'); end if;

  select * into k from sz_kullanimlar where sezlong_id = s.id and bitti is null;
  v_benim := k.id is not null and p_oda is not null and k.oda = sz_oda(p_oda);

  return json_build_object(
    'ok', true, 'kod', s.kod, 'alan', s.alan_adi, 'alan_id', s.alan_id, 'otel', a.otel_adi,
    'durum', case when s.kapali then 'kapali'
                  when k.id is null then 'bos'
                  when k.uyari_zamani is not null then 'uyari'
                  else 'dolu' end,
    'benim', v_benim,
    'basladi', case when v_benim then k.basladi end,
    'uyari_bitis', case when v_benim and k.uyari_zamani is not null
                        then k.uyari_zamani + make_interval(mins => a.uyari_sure_dk) end,
    'uyari_sure_dk', a.uyari_sure_dk,
    'oda_basi_max', a.oda_basi_max
  );
end $$;

create or replace function public.misafir_al(p_kod text, p_oda text) returns json
language plpgsql security definer set search_path = public as $$
declare s record; k record; a sz_ayarlar; v_oda text := sz_oda(p_oda); v_adet int;
begin
  perform sz_eski_kapat();
  select * into a from sz_ayarlar where id = 1;
  if v_oda !~ a.oda_regex then return json_build_object('ok', false, 'hata', 'oda'); end if;

  select sz.id, sz.kapali into s from sz_sezlonglar sz join sz_alanlar al on al.id = sz.alan_id
   where sz.kod = upper(trim(p_kod)) and sz.aktif and al.aktif for update of sz;
  if s.id is null then return json_build_object('ok', false, 'hata', 'bulunamadi'); end if;
  if s.kapali then return json_build_object('ok', false, 'hata', 'kapali'); end if;

  select * into k from sz_kullanimlar where sezlong_id = s.id and bitti is null;
  if k.id is not null then
    if k.oda = v_oda then
      update sz_kullanimlar set son_onay = now(), uyari_zamani = null where id = k.id;
      return json_build_object('ok', true, 'sonuc', 'zaten_sizin');
    end if;
    return json_build_object('ok', false, 'hata', 'dolu');
  end if;

  select count(*) into v_adet from sz_kullanimlar where oda = v_oda and bitti is null;
  if v_adet >= a.oda_basi_max then
    return json_build_object('ok', false, 'hata', 'limit', 'limit', a.oda_basi_max);
  end if;

  begin
    insert into sz_kullanimlar (sezlong_id, oda) values (s.id, v_oda);
  exception when unique_violation then
    return json_build_object('ok', false, 'hata', 'dolu');
  end;
  return json_build_object('ok', true, 'sonuc', 'alindi');
end $$;

create or replace function public.misafir_buradayim(p_kod text, p_oda text) returns json
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update sz_kullanimlar k set son_onay = now(), uyari_zamani = null
    from sz_sezlonglar sz
   where sz.id = k.sezlong_id and sz.kod = upper(trim(p_kod))
     and k.bitti is null and k.oda = sz_oda(p_oda);
  get diagnostics n = row_count;
  return json_build_object('ok', n > 0);
end $$;

create or replace function public.misafir_birak(p_kod text, p_oda text) returns json
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update sz_kullanimlar k set bitti = now(), bitis_nedeni = 'misafir'
    from sz_sezlonglar sz
   where sz.id = k.sezlong_id and sz.kod = upper(trim(p_kod))
     and k.bitti is null and k.oda = sz_oda(p_oda);
  get diagnostics n = row_count;
  return json_build_object('ok', n > 0);
end $$;

create or replace function public.misafir_sezlonglarim(p_oda text) returns json
language sql security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('kod', sz.kod, 'alan', al.ad,
                  'uyari', k.uyari_zamani is not null) order by k.basladi), '[]'::json)
    from sz_kullanimlar k join sz_sezlonglar sz on sz.id = k.sezlong_id join sz_alanlar al on al.id = sz.alan_id
   where k.bitti is null and k.oda = sz_oda(p_oda)
     and (k.basladi at time zone 'Europe/Istanbul')::date = sz_bugun();
$$;

-- Canlı doluluk (oda numarası içermez – herkese açık)
create or replace function public.alan_doluluk() returns json
language sql security definer set search_path = public as $$
  select coalesce(json_agg(x order by x.sira, x.ad), '[]'::json) from (
    select al.id, al.kod, al.ad, al.sira,
           count(sz.id) filter (where not sz.kapali)                                   as toplam,
           count(k.id)  filter (where not sz.kapali
                                and (k.basladi at time zone 'Europe/Istanbul')::date = sz_bugun()) as dolu
      from sz_alanlar al
      left join sz_sezlonglar sz on sz.alan_id = al.id and sz.aktif
      left join sz_kullanimlar k on k.sezlong_id = sz.id and k.bitti is null
     where al.aktif
     group by al.id
  ) x;
$$;

-- ---------- GÖREVLİ FONKSİYONLARI ----------

create or replace function public.gorevli_durum() returns json
language plpgsql security definer set search_path = public as $$
declare r json;
begin
  if not sz_personel_mi() then raise exception 'yetkisiz'; end if;
  perform sz_eski_kapat();
  select json_build_object(
    'ayarlar', (select row_to_json(a) from sz_ayarlar a where id = 1),
    'simdi', now(),
    'alanlar', (select coalesce(json_agg(al order by al.sira, al.ad), '[]'::json) from sz_alanlar al where al.aktif),
    'sezlonglar', (select coalesce(json_agg(json_build_object(
          'id', sz.id, 'alan_id', sz.alan_id, 'no', sz.no, 'kod', sz.kod, 'kapali', sz.kapali,
          'k_id', k.id, 'oda', k.oda, 'basladi', k.basladi, 'son_onay', k.son_onay,
          'uyari_zamani', k.uyari_zamani, 'gorevli_ile', k.gorevli_ile) order by sz.alan_id, sz.no), '[]'::json)
        from sz_sezlonglar sz
        left join sz_kullanimlar k on k.sezlong_id = sz.id and k.bitti is null
       where sz.aktif)
  ) into r;
  return r;
end $$;

create or replace function public.gorevli_islem(p_sezlong_id int, p_islem text, p_oda text default null) returns json
language plpgsql security definer set search_path = public as $$
declare a sz_ayarlar; v_oda text := sz_oda(p_oda); v_adet int; n int := 0;
begin
  if not sz_personel_mi() then raise exception 'yetkisiz'; end if;
  perform sz_eski_kapat();
  select * into a from sz_ayarlar where id = 1;

  if p_islem = 'uyari' then
    update sz_kullanimlar set uyari_zamani = now() where sezlong_id = p_sezlong_id and bitti is null and uyari_zamani is null;
  elsif p_islem = 'uyari_iptal' then
    update sz_kullanimlar set uyari_zamani = null, son_onay = now() where sezlong_id = p_sezlong_id and bitti is null;
  elsif p_islem in ('bosalt', 'terk') then
    update sz_kullanimlar set bitti = now(), bitis_nedeni = case when p_islem = 'terk' then 'terk' else 'gorevli' end
     where sezlong_id = p_sezlong_id and bitti is null;
  elsif p_islem = 'doldur' then
    if v_oda !~ a.oda_regex then return json_build_object('ok', false, 'hata', 'oda'); end if;
    if exists (select 1 from sz_sezlonglar where id = p_sezlong_id and kapali) then
      return json_build_object('ok', false, 'hata', 'kapali'); end if;
    select count(*) into v_adet from sz_kullanimlar where oda = v_oda and bitti is null;
    if v_adet >= a.oda_basi_max then return json_build_object('ok', false, 'hata', 'limit', 'limit', a.oda_basi_max); end if;
    begin
      insert into sz_kullanimlar (sezlong_id, oda, gorevli_ile) values (p_sezlong_id, v_oda, true);
    exception when unique_violation then return json_build_object('ok', false, 'hata', 'dolu');
    end;
  elsif p_islem = 'kapat' then
    update sz_kullanimlar set bitti = now(), bitis_nedeni = 'gorevli' where sezlong_id = p_sezlong_id and bitti is null;
    update sz_sezlonglar set kapali = true where id = p_sezlong_id;
  elsif p_islem = 'ac' then
    update sz_sezlonglar set kapali = false where id = p_sezlong_id;
  else
    return json_build_object('ok', false, 'hata', 'islem');
  end if;
  get diagnostics n = row_count;
  return json_build_object('ok', true, 'etkilenen', n);
end $$;

-- ---------- YÖNETİCİ FONKSİYONLARI ----------

create or replace function public.admin_sezlong_ekle(p_alan_id int, p_adet int) returns json
language plpgsql security definer set search_path = public as $$
declare v_kod text; v_max int;
begin
  if not sz_admin_mi() then raise exception 'yetkisiz'; end if;
  if p_adet < 1 or p_adet > 1000 then return json_build_object('ok', false, 'hata', 'adet'); end if;
  select kod into v_kod from sz_alanlar where id = p_alan_id;
  if v_kod is null then return json_build_object('ok', false, 'hata', 'alan'); end if;
  select coalesce(max(no), 0) into v_max from sz_sezlonglar where alan_id = p_alan_id;
  insert into sz_sezlonglar (alan_id, no, kod)
  select p_alan_id, g, v_kod || '-' || lpad(g::text, 3, '0') from generate_series(v_max + 1, v_max + p_adet) g;
  return json_build_object('ok', true, 'ilk', v_max + 1, 'son', v_max + p_adet);
end $$;

create or replace function public.admin_gun_sonu() returns json
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not sz_admin_mi() then raise exception 'yetkisiz'; end if;
  update sz_kullanimlar set bitti = now(), bitis_nedeni = 'gun_sonu' where bitti is null;
  get diagnostics n = row_count;
  return json_build_object('ok', true, 'kapatilan', n);
end $$;

-- Günlük rapor: saatlik kullanılan şezlong sayısı (alan bazında) + özet
create or replace function public.admin_rapor(p_tarih date) returns json
language plpgsql security definer set search_path = public as $$
declare r json;
begin
  if not sz_admin_mi() then raise exception 'yetkisiz'; end if;
  with saatler as (
    select h, ((p_tarih + make_time(h, 0, 0)) at time zone 'Europe/Istanbul') as bas
      from generate_series(7, 20) h
  ), gunluk as (
    select k.*, sz.alan_id from sz_kullanimlar k join sz_sezlonglar sz on sz.id = k.sezlong_id
     where (k.basladi at time zone 'Europe/Istanbul')::date = p_tarih
  ), alan_toplam as (
    select al.id, al.ad, al.sira, count(sz.id) filter (where sz.aktif) as toplam
      from sz_alanlar al left join sz_sezlonglar sz on sz.alan_id = al.id group by al.id
  )
  select json_build_object(
    'tarih', p_tarih,
    'ozet', (select json_build_object(
        'toplam_kullanim', count(*),
        'farkli_oda', count(distinct oda),
        'ort_sure_dk', round(avg(extract(epoch from (coalesce(bitti, now()) - basladi)) / 60)),
        'misafir_birakti', count(*) filter (where bitis_nedeni = 'misafir'),
        'gorevli_bosaltti', count(*) filter (where bitis_nedeni = 'gorevli'),
        'terk', count(*) filter (where bitis_nedeni = 'terk'),
        'uyari_verilen', count(*) filter (where uyari_zamani is not null),
        'gorevli_ile', count(*) filter (where gorevli_ile)) from gunluk),
    'alanlar', (select coalesce(json_agg(json_build_object(
        'id', t.id, 'ad', t.ad, 'toplam', t.toplam,
        'saatler', (select json_agg(json_build_object('saat', s.h, 'kullanilan',
                      (select count(distinct g.sezlong_id) from gunluk g
                        where g.alan_id = t.id and g.basladi < s.bas + interval '1 hour'
                          and coalesce(g.bitti, now()) > s.bas)) order by s.h) from saatler s)
      ) order by t.sira, t.ad), '[]'::json) from alan_toplam t)
  ) into r;
  return r;
end $$;

-- ---------- GÜVENLİK (RLS) ----------

alter table public.sz_ayarlar     enable row level security;
alter table public.sz_alanlar     enable row level security;
alter table public.sz_sezlonglar  enable row level security;
alter table public.sz_kullanimlar enable row level security;
alter table public.sz_personel    enable row level security;

drop policy if exists ayarlar_oku on public.sz_ayarlar;
create policy ayarlar_oku on public.sz_ayarlar for select using (true);
drop policy if exists ayarlar_yaz on public.sz_ayarlar;
create policy ayarlar_yaz on public.sz_ayarlar for update using (sz_admin_mi()) with check (sz_admin_mi());

drop policy if exists alanlar_oku on public.sz_alanlar;
create policy alanlar_oku on public.sz_alanlar for select using (true);
drop policy if exists alanlar_yaz on public.sz_alanlar;
create policy alanlar_yaz on public.sz_alanlar for all using (sz_admin_mi()) with check (sz_admin_mi());

drop policy if exists sezlonglar_oku on public.sz_sezlonglar;
create policy sezlonglar_oku on public.sz_sezlonglar for select using (sz_personel_mi());
drop policy if exists sezlonglar_yaz on public.sz_sezlonglar;
create policy sezlonglar_yaz on public.sz_sezlonglar for all using (sz_admin_mi()) with check (sz_admin_mi());

-- Oda numaraları yalnızca sz_personel tarafından görülebilir; yazma işlemleri sadece fonksiyonlar üzerinden
drop policy if exists kullanimlar_oku on public.sz_kullanimlar;
create policy kullanimlar_oku on public.sz_kullanimlar for select using (sz_personel_mi());

drop policy if exists personel_oku on public.sz_personel;
create policy personel_oku on public.sz_personel for select using (user_id = auth.uid() or sz_admin_mi());

-- Fonksiyon yetkileri
-- (yalnızca bu sistemin fonksiyonları – projedeki diğer fonksiyonlara dokunulmaz)
revoke execute on function public.sz_eski_kapat(), public.gorevli_durum(), public.gorevli_islem(int, text, text),
  public.admin_sezlong_ekle(int, int), public.admin_gun_sonu(), public.admin_rapor(date)
  from public, anon, authenticated;
grant execute on function public.misafir_sezlong(text, text), public.misafir_al(text, text),
  public.misafir_buradayim(text, text), public.misafir_birak(text, text),
  public.misafir_sezlonglarim(text), public.alan_doluluk(),
  public.sz_bugun(), public.sz_oda(text), public.sz_personel_mi(), public.sz_admin_mi()
  to anon, authenticated;
grant execute on function public.gorevli_durum(), public.gorevli_islem(int, text, text),
  public.admin_sezlong_ekle(int, int), public.admin_gun_sonu(), public.admin_rapor(date)
  to authenticated;

-- Tablo yetkileri (RLS kuralları ayrıca uygulanır)
grant usage on schema public to anon, authenticated;
grant select on public.sz_ayarlar, public.sz_alanlar to anon, authenticated;
grant update on public.sz_ayarlar to authenticated;
grant select, insert, update, delete on public.sz_alanlar, public.sz_sezlonglar to authenticated;
grant select on public.sz_kullanimlar, public.sz_personel to authenticated;
grant usage on sequence public.sz_alanlar_id_seq, public.sz_sezlonglar_id_seq to authenticated;

-- Görevli paneli için anlık güncelleme (Realtime)
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.sz_kullanimlar; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.sz_sezlonglar;  exception when duplicate_object then null; end;
  end if;
end $$;

-- ---------- BAŞLANGIÇ ALANLARI (isteğe bağlı – panelden de eklenebilir) ----------
insert into public.sz_alanlar (kod, ad, sira) values ('S', 'Sahil', 1), ('H', 'Ana Havuz', 2)
on conflict (kod) do nothing;
