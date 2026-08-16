#!/bin/sh
set -eu

root=$(mktemp -d "${TMPDIR:-/tmp}/distribution-prepare.XXXXXX")
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
script=$script_dir/prepare_article.sh
caption_prefix=$(printf '\345\233\276\346\263\250\357\274\232')
legacy_caption_prefix=$(printf '\345\233\276\357\274\232')
caption='The deterministic system verifies AI candidates.'
reading_prefix=$(printf '\345\205\250\346\226\207\347\272\246')
reading_middle=$(printf '\345\255\227\357\274\214\351\242\204\350\256\241\351\230\205\350\257\273')
reading_suffix=$(printf '\345\210\206\351\222\237')
reading_notice="$reading_prefix 5200 $reading_middle 11 $reading_suffix"

cleanup() {
    rm -rf -- "$root"
}
trap cleanup EXIT HUP INT TERM

: > "$root/cover.png"
: > "$root/body.png"

for platform in wechat zhihu csdn juejin; do
    article=$root/$platform.md
    output=$root/$platform-output
    {
        printf '%s\n' '---'
        printf 'platform: %s\n' "$platform"
        printf '%s\n' 'title: "Native payload test"' 'cover: "cover.png"' '---' ''
        printf '%s\n\n' "$reading_notice"
        printf '%s\n\n' '![Testing loop diagram](body.png)'
        if [ "$platform" = zhihu ]; then source_caption_prefix=$legacy_caption_prefix; else source_caption_prefix=$caption_prefix; fi
        printf '%s%s\n' "$source_caption_prefix" "$caption"
    } > "$article"

    sh "$script" --platform "$platform" --input "$article" --output "$output" >/dev/null
    grep -q '"schema_version": 2' "$output/manifest.json"
    grep -q '"alt": "Testing loop diagram"' "$output/manifest.json"
    grep -q '"caption": "The deterministic system verifies AI candidates."' "$output/manifest.json"
    grep -q '"role": "informative"' "$output/manifest.json"
    [ "$(grep -Fc "$caption" "$output/body.html")" -eq 1 ]
    [ "$(grep -Fc "$reading_notice" "$output/body.html")" -eq 1 ]
    [ "$(grep -Fc 'data-reading-notice="true"' "$output/body.html")" -eq 1 ]

    if [ "$platform" = wechat ]; then
        grep -q 'data-image-caption="true"' "$output/body.html"
        grep -q 'font-size:13px' "$output/body.html"
        grep -q 'background:#f8f4ec' "$output/body.html"
    else
        grep -q '<figcaption>' "$output/body.html"
        grep -q 'font-size:14px' "$output/body.html"
        grep -q 'background:#f7f7f7' "$output/body.html"
    fi

    if [ "$platform" = csdn ] || [ "$platform" = juejin ]; then
        grep -Fq "*$caption_prefix$caption*" "$output/body.md"
        grep -Fq "*$reading_notice*" "$output/body.md"
    else
        grep -Fxq "$reading_notice" "$output/body.md"
    fi
done

cat > "$root/missing.md" <<EOF
---
platform: wechat
title: "Missing caption"
cover: "cover.png"
---

![Informative image](body.png)
EOF
if sh "$script" --platform wechat --input "$root/missing.md" --output "$root/missing-output" >/dev/null 2>&1; then
    printf '%s\n' 'Informative image without caption unexpectedly passed.' >&2
    exit 1
fi

cat > "$root/orphan.md" <<EOF
---
platform: wechat
title: "Orphan caption"
cover: "cover.png"
---

$caption_prefix$caption
EOF
if sh "$script" --platform wechat --input "$root/orphan.md" --output "$root/orphan-output" >/dev/null 2>&1; then
    printf '%s\n' 'Orphan caption unexpectedly passed.' >&2
    exit 1
fi

cat > "$root/decorative.md" <<EOF
---
platform: wechat
title: "Decorative image"
cover: "cover.png"
---

![](body.png)
EOF
sh "$script" --platform wechat --input "$root/decorative.md" --output "$root/decorative-output" >/dev/null
grep -q '"role": "decorative"' "$root/decorative-output/manifest.json"

cat > "$root/decorative-caption.md" <<EOF
---
platform: wechat
title: "Decorative image with caption"
cover: "cover.png"
---

![](body.png)

$caption_prefix$caption
EOF
if sh "$script" --platform wechat --input "$root/decorative-caption.md" --output "$root/decorative-caption-output" >/dev/null 2>&1; then
    printf '%s\n' 'Decorative image with caption unexpectedly passed.' >&2
    exit 1
fi

if sh "$script" --platform zhihu --input "$root/wechat.md" --output "$root/platform-mismatch-output" >/dev/null 2>&1; then
    printf '%s\n' 'Platform mismatch unexpectedly passed.' >&2
    exit 1
fi

cat > "$root/caption-inside-code.md" <<EOF
---
platform: csdn
title: "Caption text inside code"
cover: "cover.png"
---

\`\`\`text
$caption_prefix$caption
\`\`\`
EOF
sh "$script" --platform csdn --input "$root/caption-inside-code.md" --output "$root/caption-inside-code-output" >/dev/null

printf '%s\n' '{"ok":true,"checks":27}'
