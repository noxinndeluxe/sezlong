# Dijital Şezlong Yönetim Sistemi – Kurulum Rehberi (Faz 1)

## Dosyalar

| Dosya | Kim kullanır | Ne yapar |
|---|---|---|
| `sezlong.html` | Misafir (QR ile açılır) | Şezlong alma, "Buradayım", bırakma, canlı doluluk. Dört dil: TR / EN / DE / RU |
| `sezlong-gorevli.html` | Plaj ve havuz görevlileri (tablet) | Renkli şezlong haritası, uyarı kartı sayacı, boşaltma, misafir adına verme |
| `sezlong-admin.html` | Yönetici | Alan ve şezlong tanımlama, QR etiket basımı, kurallar, günlük rapor |
| `sezlong-config.js` | Hepsi | Supabase bağlantı bilgileri |
| `sezlong-schema.sql` | Bir kez çalıştırılır | Veritabanı tabloları, güvenlik kuralları ve fonksiyonlar |

Altyapının tamamı ücretsiz: Supabase Free planı ve GitHub Pages.

---

## 1. Supabase projesi

1. https://supabase.com adresinden ücretsiz bir proje açın. Mevcut bir projenizi de kullanabilirsiniz: bu sistemin bütün tabloları `sz_` ile başladığı için diğer tablolarınızla çakışmaz.
2. Sol menüden **SQL Editor > New query** açın, `sezlong-schema.sql` dosyasının tamamını yapıştırıp **Run**'a basın.
   - Kurulum "Sahil (S)" ve "Ana Havuz (H)" alanlarını boş olarak oluşturur. Şezlongları panelden ekleyeceksiniz.

> **Not:** Supabase'in ücretsiz planı, 7 gün boyunca hiç kullanılmayan projeyi duraklatır. Sezon boyunca her gün kullanıldığı için sorun çıkmaz. Kışın duraklarsa panelden **Restore** ile tekrar açılır, veriler silinmez.

## 2. Personel hesapları

1. **Authentication > Users > Add user > Create new user** yolunu izleyin. E-posta ve şifre girin, **Auto Confirm User** seçeneğini işaretleyin.
   - Yönetici hesabı için örnek: `sezlong-admin@noxinn...`
   - Tablet hesapları için örnek: `plaj1@...`, `havuz1@...` (tablet başına bir hesap açmanız önerilir)
2. Hesapları sisteme tanıtmak için **SQL Editor**'da şunu çalıştırın:

```sql
insert into sz_personel (user_id, ad, rol)
select id, 'Dragut', 'admin' from auth.users where email = 'sezlong-admin@ORNEK.com';

insert into sz_personel (user_id, ad, rol)
select id, 'Plaj Tableti 1', 'gorevli' from auth.users where email = 'plaj1@ORNEK.com';
```

`admin` rolündeki hesaplar hem yönetim panelini hem görevli panelini kullanabilir. `gorevli` rolündekiler yalnızca görevli panelini kullanabilir.

## 3. Bağlantı ayarı

**Project Settings > API** sayfasındaki **Project URL** ve **anon public** anahtarını `sezlong-config.js` dosyasına yazın.
⚠️ `service_role` anahtarını hiçbir zaman bu dosyaya yazmayın.

## 4. Yayınlama (GitHub Pages – ücretsiz)

1. GitHub'da yeni bir repo açın (örneğin `sezlong`) ve 4 dosyayı yükleyin: `sezlong.html`, `sezlong-gorevli.html`, `sezlong-admin.html`, `sezlong-config.js`.
2. **Settings > Pages** sayfasında **Branch: main / root** seçip kaydedin.
3. Birkaç dakika sonra adresler hazır olur:
   - Misafir: `https://KULLANICI.github.io/sezlong/sezlong.html`
   - Görevli: `https://KULLANICI.github.io/sezlong/sezlong-gorevli.html`
   - Yönetim: `https://KULLANICI.github.io/sezlong/sezlong-admin.html`

## 5. İlk ayarlar ve QR basımı

1. Yönetim paneline girin ve **Ayarlar** sekmesinde **Misafir sayfası adresi** alanına misafir sayfasının adresini yazın. Bu adımı mutlaka QR basmadan önce yapın.
2. **Alanlar & Şezlonglar** sekmesinde Sahil için 300, Ana Havuz için 150 adet girip **Ekle**'ye basın. S-001…S-300 ve H-001…H-150 kodları otomatik oluşur.
   - Daha sonra şezlong eklemek isterseniz numaralandırma kaldığı yerden devam eder.
   - Kaldırılan şezlongun numarasına tıklayarak onu pasif yapabilirsiniz. Kodlar ve basılı QR'lar bozulmaz.
3. **QR Etiketleri** sekmesinde alanı ve numara aralığını seçip **Etiketleri oluştur**'a, ardından **Yazdır**'a basın. Her A4 sayfaya 9 etiket sığar.
   - Etiketleri UV'ye ve suya dayanıklı etiket kâğıdına basın ya da lamine edin.
   - Lobi ve havlu masası için **Genel doluluk afişi** de basabilirsiniz.
4. Basmadan önce birkaç etiketi telefonla okutup deneyin.

## 6. Kurallar (Ayarlar sekmesinden değiştirilebilir)

| Ayar | Varsayılan | Anlamı |
|---|---|---|
| Kontrol et süresi | 75 dk | Misafir bu süre boyunca QR'ı tekrar okutmazsa veya "Buradayım"a dokunmazsa şezlong panelde turuncu çerçeveyle işaretlenir |
| Uyarı kartı süresi | 30 dk | Görevli uyarı kartı bıraktıktan sonra misafirin dönmesi için tanınan süre |
| Oda başına şezlong | 4 | Bir odanın aynı anda tutabileceği şezlong sayısı |
| Oda numarası formatı | 3–4 hane | Villa gibi harfli odalar varsa değiştirilmelidir |
| Kapanış saati | 19:00 | Boşaltılmayan şezlonglar ertesi gün otomatik olarak bu saatte kapatılmış sayılır |

## 7. Görevli paneli renkleri

- ⬜ **Boş**
- 🟦 **Dolu** (misafirin oda numarası görünür)
- 🟦 + turuncu çerçeve ve **!** işareti: **Kontrol et.** Misafir uzun süredir onay vermedi, şezlonga bakılmalı.
- 🟧 **Uyarı kartında.** Geri sayım devam ediyor.
- 🟥 (yanıp söner) **Boşaltılabilir.** Uyarı süresi doldu.
- ▨ **Kapalı** (bakım vb.)

Görevli, bir şezlongun üzerinde sadece havlu olduğunu görünce şezlonga dokunur ve **Uyarı kartı bıraktım**'ı seçer. Misafir QR'ı okutursa ya da "Buradayım"a dokunursa uyarı kendiliğinden kalkar. Misafir süre içinde dönmezse şezlong **Terk – boşalt** ile diğer misafirlere açılır. Her işlem saatiyle kaydedildiği için olası bir tartışmada kayıt elinizde olur.

## 8. Güvenlik ve KVKK

- Misafirden yalnızca oda numarası alınır. İsim, telefon veya başka bir kişisel veri tutulmaz.
- Canlı doluluk ekranı oda numarası göstermez. Oda numaralarını yalnızca giriş yapmış personel görebilir.
- Misafir işlemleri yalnızca veritabanı fonksiyonları üzerinden yapılabilir, tablolara doğrudan yazılamaz.

## 9. Pilot önerisi

İlk olarak tek bir havuz alanında 2–3 hafta pilot yapın. Bu sürede **Rapor** sekmesindeki saatlik doluluk, terk sayıları ve görevli tarafından misafir adına verilen şezlong oranını takip edin. Bu son oran, misafirlerin sistemi ne kadar kendi başına kullandığını gösterir. Sahile geçmeden önce plajda Wi-Fi kapsamasını kontrol etmeyi unutmayın.
