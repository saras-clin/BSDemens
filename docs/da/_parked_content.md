# Parkeret indhold

Nedenstående tekst er fjernet fra `00_index.qmd` da det var en manuel indholdsliste
der nu er erstattet af sidebar-navigationens fase-struktur.

---

## Indhold (gammel liste fra index.qmd)

**Generelt**

- [Studieforberedelse](01_studieforberedelse.qmd) — analyseplan, STROBE, hvad er DST
- [Ressourcer og hjælp](02b_ressourcer-og-hjaelp.qmd) — hjælpeliste, kurser, AI-tips

**R og RStudio**

- [Kom i gang med R](02a_r-intro.qmd) — RStudio, første projekt, genveje
- [Datastrukturer](10a_datastrukturer.qmd) — langt og bredt format
- [Basiskommandoer](07_basiskommandoer.qmd) — udforsk og forstå dine data
- [Filformater](04_filformater.qmd) — SAS, Parquet, RDS, CSV

**DST-serveren**

- [Kom i gang på DST](03_getting-started-dst.qmd) — de første 10 minutter, det universelle mønster
- [Parquet, Arrow og DuckDB](05_parquet-arrow-duckdb.qmd) — doven evaluering, collect(), RAM

**Kode og data**

- [Første udtræk](06_foerste-udtraek.qmd) — trin-for-trin fra register til gemt datasæt
- [Funktioner — oversigt](13a_guide_til_funktioner.qmd) — filter, select, mutate, joins
- [Joins og pivots](10b_joins-og-pivots.qmd) — kobl datasæt sammen
- [Formateringstabeller](13b_formateringstabeller.qmd) — oversæt koder til tekst
- [Hospitalskontakter (LPR)](09_hospitalskontakter-lpr.qmd) — LPR2 + LPR3, ICD-koder
- [Socioøkonomiske variable](11a_socioekonomiske-variable.qmd) — uddannelse, indkomst, beskæftigelse

**Pakker og algoritmer**

- [Oversigt](12a_pakker-oversigt.qmd) — OSDC, NMI og SEPLINE
- [OSDC](12b_osdc.qmd) — Open Source Diabetes Classifier
- [NMI](12c_nmi.qmd) — Nordic Multimorbidity Index
- [SEPLINE](11b_sepline.qmd) — socioøkonomisk position

**Reference og hjemsendelse**

- [Registerreference](08_register_reference.qmd) — bekræftede kolonnenavne for alle registre
- [Faldgruber](13c_dst_faldgruber.qmd) — 10 DST-specifikke fejl
- [Eksport og hjemsendelse](14_eksport-hjemsendelse.qmd) — GDPR og outputkontrol

---

## "Hvad er SDS og DST?" (fra 01_studieforberedelse.qmd, afsnit 3)

Som forsker arbejder du på **Danmarks Statistiks (DST) servere**.
DST modtager og bearbejder data fra bl.a. Sundhedsdatastyrelsen (SDS), som har de rå nationale sundhedsregistre (LPR, LMDB, cancerregister mv.), og stiller dem til rådighed for forskere via sikker fjernforbindelse.
