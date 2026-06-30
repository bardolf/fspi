#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Interaktivní přetagování MP3 pro Audiobookshelf.

Co to dělá:
  * Opraví rozbitou diakritiku (bajty Windows-1250 chybně uložené jako ISO-8859-1
    -> "vypravìè" se vrátí na "vypravěč").
  * Zeptá se JEDNOU na společné údaje knihy (s předvyplněnými rozumnými defaulty).
  * U každého souboru nabídne unikátní věci (název stopy, číslo stopy).
  * Zapíše čisté ID3v2.4 (UTF-8) a SMAŽE ID3v1 + APE + starý Adobe XMP balast.
  * Před zápisem udělá zálohu originálů (mimo cílovou složku, aby se nedostala do ABS).

Pozn. k ABS: údaje o KNIZE (název, autor, vypravěč, rok, žánr, popis) bere ABS
jen z PRVNÍHO souboru; název stopy (TIT2) a číslo stopy (TRCK) z každého zvlášť.

Použití:
  python3 retag_id3.py [SLOŽKA]      (výchozí = aktuální složka)
"""

import os
import re
import sys
import glob
import shutil

try:
    from mutagen.id3 import (ID3, ID3NoHeaderError,
                             TIT2, TALB, TPE1, TPE2, TCOM, TCON, TDRC, TRCK,
                             COMM, APIC)
    from mutagen.apev2 import APEv2, APENoHeaderError
except ImportError:
    sys.exit("Chybí balík 'mutagen'.  Nainstaluj:  pip install mutagen")


# ----------------------------------------------------------------------------
# Pomocné funkce
# ----------------------------------------------------------------------------

def natkey(name):
    """Přirozené řazení (1,2,...,10 místo 1,10,2)."""
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r'(\d+)', name)]


def fix_latin1_cp1250(text, encoding):
    """ID3v2 rámec deklarovaný jako Latin-1 (encoding==0), ale bajty jsou CP1250.
    Tohle je přesně případ těchhle souborů. U UTF-8/UTF-16 rámců nesaháme."""
    if encoding == 0 and text:
        try:
            return text.encode('latin-1').decode('cp1250')
        except (UnicodeEncodeError, UnicodeDecodeError):
            return text
    return text


def read_text(tags, key):
    """Vrátí první textovou hodnotu rámce s opravenou diakritikou."""
    fr = tags.get(key)
    if not fr or not getattr(fr, 'text', None):
        return ''
    return fix_latin1_cp1250(str(fr.text[0]), getattr(fr, 'encoding', 3)).strip()


def read_comment(tags):
    for fr in tags.getall('COMM'):
        if fr.desc.lower().startswith('id3v1'):
            continue  # přeskoč oříznutou ID3v1 kopii
        if fr.text:
            return fix_latin1_cp1250(str(fr.text[0]), getattr(fr, 'encoding', 3)).strip()
    return ''


def smart_case(s):
    """KAPITÁLKY -> Hezký Zápis (pro album/autora). Jinak nech být."""
    letters = [c for c in s if c.isalpha()]
    if letters and s == s.upper():
        return s.title()
    return s


def strip_track_prefix(title):
    """Odstraní vedoucí číslo stopy, např. '01 Portrét' -> 'Portrét'."""
    return re.sub(r'^\s*\d+\s*[-_.)]?\s+', '', (title or '')).strip()


def ask(label, default=''):
    suffix = "  [%s]" % default if default else ""
    try:
        val = input("%s%s: " % (label, suffix)).strip()
    except EOFError:
        val = ''
    return val if val else default


def yesno(label, default_yes=False):
    d = "A/n" if default_yes else "a/N"
    try:
        val = input("%s [%s]: " % (label, d)).strip().lower()
    except EOFError:
        val = ''
    if not val:
        return default_yes
    return val in ('a', 'ano', 'y', 'yes')


# ----------------------------------------------------------------------------
# Hlavní program
# ----------------------------------------------------------------------------

def main():
    target = sys.argv[1] if len(sys.argv) > 1 else '.'
    target = os.path.abspath(target)
    if not os.path.isdir(target):
        sys.exit("Není složka: %s" % target)

    files = sorted(glob.glob(os.path.join(target, '*.mp3')),
                   key=lambda p: natkey(os.path.basename(p)))
    if not files:
        sys.exit("Ve složce nejsou žádné .mp3: %s" % target)

    print("\nSložka: %s" % target)
    print("Nalezeno %d souborů. ABS bere údaje o knize z prvního: %s\n"
          % (len(files), os.path.basename(files[0])))

    # ---- defaulty z PRVNÍHO souboru -------------------------------------
    try:
        first = ID3(files[0])
    except ID3NoHeaderError:
        first = ID3()

    d_album   = smart_case(read_text(first, 'TALB')) or os.path.basename(target)
    d_artist  = smart_case(read_text(first, 'TPE1') or read_text(first, 'TPE2'))
    d_composer = read_text(first, 'TCOM') or "Jaroslav Konečný"
    d_genre   = read_text(first, 'TCON') or "Rozhlasová dramatizace"
    d_year    = (read_text(first, 'TDRC') or read_text(first, 'TYER'))[:4]
    d_comment = read_comment(first)

    print("=== Společné údaje knihy (vyplní se do VŠECH souborů) ===")
    album      = ask("Název knihy (Album)", d_album)
    artist     = ask("Autor (Artist)", d_artist)
    albumartist = ask("Album Artist", artist)
    composer   = ask("Vypravěč (Composer)", d_composer)
    genre      = ask("Žánr (Genre)", d_genre)
    year       = ask("Rok (Year)", d_year)
    comment    = ask("Popis / účinkující (Comment)", d_comment)

    # ---- obal -----------------------------------------------------------
    imgs = []
    for ext in ('*.jpg', '*.jpeg', '*.png'):
        imgs += glob.glob(os.path.join(target, ext))
    has_embedded = bool(first.getall('APIC'))
    if imgs:
        d_cover = imgs[0]
    elif has_embedded:
        d_cover = 'embedded'
    else:
        d_cover = 'ne'
    print("\n=== Obal ===  (cesta k souboru / 'embedded' = ponechat stávající / 'ne')")
    cover_in = ask("Obal", d_cover)

    cover_data = cover_mime = None
    if cover_in.lower() == 'embedded' and has_embedded:
        apic = first.getall('APIC')[0]
        cover_data, cover_mime = apic.data, (apic.mime or 'image/jpeg')
    elif cover_in.lower() not in ('ne', 'no', ''):
        if os.path.isfile(cover_in):
            with open(cover_in, 'rb') as fh:
                cover_data = fh.read()
            cover_mime = 'image/png' if cover_in.lower().endswith('.png') else 'image/jpeg'
        else:
            print("  !! soubor s obalem nenalezen, obal se nevloží")

    # ---- per-file: název + číslo stopy ----------------------------------
    per = []
    for idx, path in enumerate(files, start=1):
        try:
            t = ID3(path)
        except ID3NoHeaderError:
            t = ID3()
        raw_title = read_text(t, 'TIT2')
        stem = os.path.splitext(os.path.basename(path))[0]
        title = strip_track_prefix(raw_title) or strip_track_prefix(stem)
        m = re.match(r'\s*(\d+)', read_text(t, 'TRCK') or stem)
        track = m.group(1) if m else str(idx)
        per.append({'path': path, 'title': title, 'track': "%d/%d" % (int(track), len(files))})

    print("\n=== Názvy stop (návrh) ===")
    for p in per:
        print("  %s  %s" % (p['track'].split('/')[0].rjust(2), p['title']))

    if yesno("\nUpravit názvy/čísla stop po jednom?", default_yes=False):
        for p in per:
            print("\n  soubor: %s" % os.path.basename(p['path']))
            p['title'] = ask("    Název stopy", p['title'])
            p['track'] = ask("    Číslo stopy", p['track'])

    # ---- souhrn + potvrzení ---------------------------------------------
    print("\n" + "=" * 60)
    print("Album      : %s" % album)
    print("Autor      : %s" % artist)
    print("Album Artist: %s" % albumartist)
    print("Vypravěč   : %s" % composer)
    print("Žánr       : %s" % genre)
    print("Rok        : %s" % year)
    print("Popis      : %s" % (comment[:70] + ('…' if len(comment) > 70 else '')))
    print("Obal       : %s" % ("%d B (%s)" % (len(cover_data), cover_mime) if cover_data else "—"))
    print("-" * 60)
    for p in per:
        print("  %s  %s" % (p['track'], p['title']))
    print("=" * 60)
    print("Zapíše se ID3v2.4 (UTF-8); smaže se ID3v1 + APE + XMP.")

    if not yesno("\nZapsat do %d souborů?" % len(files), default_yes=False):
        print("Zrušeno, nic se nezměnilo.")
        return

    # ---- záloha (mimo cílovou složku!) ----------------------------------
    backup = os.path.join(os.path.dirname(target),
                          os.path.basename(target) + "_originaly_zaloha")
    os.makedirs(backup, exist_ok=True)
    for path in files:
        dst = os.path.join(backup, os.path.basename(path))
        if not os.path.exists(dst):
            shutil.copy2(path, dst)
    print("Záloha originálů: %s" % backup)

    # ---- zápis ----------------------------------------------------------
    for p in per:
        path = p['path']
        # pryč s APE
        try:
            APEv2(path).delete()
        except APENoHeaderError:
            pass
        except Exception:
            pass
        # pryč s celým starým ID3 (v1 i v2, včetně XMP PRIV)
        try:
            ID3(path).delete(delete_v1=True, delete_v2=True)
        except ID3NoHeaderError:
            pass

        tags = ID3()
        tags.add(TALB(encoding=3, text=album))
        tags.add(TPE1(encoding=3, text=artist))
        tags.add(TPE2(encoding=3, text=albumartist))
        if composer:
            tags.add(TCOM(encoding=3, text=composer))
        if genre:
            tags.add(TCON(encoding=3, text=genre))
        if year:
            tags.add(TDRC(encoding=3, text=year))
        if comment:
            tags.add(COMM(encoding=3, lang='ces', desc='', text=comment))
        tags.add(TIT2(encoding=3, text=p['title']))
        tags.add(TRCK(encoding=3, text=p['track']))
        if cover_data:
            tags.add(APIC(encoding=3, mime=cover_mime, type=3, desc='Cover', data=cover_data))
        tags.save(path, v2_version=4, v1=0)
        print("  OK  %s" % os.path.basename(path))

    print("\nHotovo. Záloha je v: %s" % backup)
    print("Tu zálohu NEnahrávej do ABS (jsou to kopie .mp3).")


if __name__ == '__main__':
    main()
