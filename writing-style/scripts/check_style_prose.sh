#!/bin/sh
# Native POSIX prose-shape checker for the writing-style skill.

fail() {
    printf '无法检查稿件：%s\n' "$1" >&2
    exit 2
}

run_check() {
    input_path=$1
    if [ "$input_path" = "-" ]; then
        set --
    else
        set -- "$input_path"
    fi

    awk '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        function excerpt(value) {
            gsub(/[[:space:]]+/, " ", value)
            value = trim(value)
            return length(value) <= 68 ? value : substr(value, 1, 67) "…"
        }
        function add(code, label, reason, value, line) {
            finding_count++
            finding_code[finding_count] = code
            finding_label[finding_count] = label
            finding_reason[finding_count] = reason
            finding_value[finding_count] = excerpt(value)
            finding_line[finding_count] = line
        }
        function starts_with(value, prefix) {
            return index(value, prefix) == 1
        }
        function sentence_starts(value, phrase, stripped) {
            stripped = trim(value)
            if (starts_with(stripped, phrase)) return 1
            return value ~ ("[。！？!?][[:space:]]*" phrase)
        }
        function flush_paragraph(    clean, compact, sentence_text, sentences, opener, i, normalized) {
            clean = trim(paragraph)
            if (clean == "") return
            if (clean ~ /^([-+*]|[0-9]+[.、])[[:space:]]/) {
                paragraph = ""
                return
            }
            compact = clean
            gsub(/[[:space:]>*_#]/, "", compact)
            if (length(compact) < 2) {
                paragraph = ""
                return
            }
            paragraph_count++
            paragraph_text[paragraph_count] = clean
            paragraph_line[paragraph_count] = paragraph_start
            paragraph_length[paragraph_count] = length(compact)
            sentence_text = clean
            sentences = gsub(/[。！？!?]/, "&", sentence_text)
            if (sentences < 1) sentences = 1
            paragraph_sentences[paragraph_count] = sentences

            if (length(compact) <= 28 && sentences <= 1) {
                short_count++
                short_text[short_count] = clean
                short_line[short_count] = paragraph_start
                if (short_count == 4)
                    add("R5", "连续短段", "连续四个短促单句段，检查是否在排队输出结论", short_text[1] " / " short_text[2] " / " short_text[3] " / " short_text[4], short_line[1])
            } else {
                short_count = 0
            }

            for (i = 1; i <= opener_total; i++) {
                opener = openers[i]
                if (starts_with(clean, opener)) {
                    opener_count[opener]++
                    if (!(opener in opener_line)) opener_line[opener] = paragraph_start
                    break
                }
            }

            normalized = compact
            gsub(/[，,；;：:。！？!?]/, "", normalized)
            if (length(normalized) >= 14 && length(normalized) <= 100) {
                if (normalized in seen_paragraph && !(normalized in reported_paragraph)) {
                    add("L6", "重复句", "与第 " seen_paragraph[normalized] " 行内容相同，检查是否需要保留两次", clean, paragraph_start)
                    reported_paragraph[normalized] = 1
                } else if (!(normalized in seen_paragraph)) {
                    seen_paragraph[normalized] = paragraph_start
                }
            }
            paragraph = ""
        }
        BEGIN {
            opener_total = split("其实 不过 当然 所以 但是 与此同时 值得注意的是 更重要的是 问题是", openers, " ")
        }
        {
            raw = $0
            if (NR == 1 && raw ~ /^---[[:space:]]*$/) {
                frontmatter = 1
                next
            }
            if (frontmatter) {
                if (raw ~ /^---[[:space:]]*$/) frontmatter = 0
                next
            }
            if (raw ~ /^[[:space:]]*(```|~~~)/) {
                fence = !fence
                flush_paragraph()
                next
            }
            if (fence || raw ~ /^[[:space:]]*>/ || raw ~ /^[[:space:]]*\|.*\|[[:space:]]*$/) {
                flush_paragraph()
                next
            }

            text = raw
            gsub(/`[^`]*`/, "", text)
            gsub(/!\[[^]]*\]\([^)]*\)/, "", text)
            gsub(/\]\([^)]*\)/, "]", text)
            gsub(/https?:\/\/[^[:space:])>]+/, "", text)
            gsub(/<[^>]*>/, "", text)
            visible = text
            gsub(/[[:space:]]/, "", visible)
            visible_count += length(visible)
            visible_position += length(text)

            if (trim(text) == "") {
                flush_paragraph()
                next
            }
            if (paragraph == "") paragraph_start = NR
            paragraph = paragraph == "" ? text : paragraph " " text

            if (visible_position <= 240 && (text ~ /在当今.*(时代|社会|技术|发展|背景|浪潮)/ || text ~ /随着.*(时代|社会|技术|发展|背景|浪潮)/))
                add("S1", "宏大通用开头", "开头没有直接进入当前问题、材料或判断", text, NR)
            if (text ~ /(接下来|下面)(我们)?(将|会|来)?.*(分析|探讨|介绍|展开|说明|看看)/)
                add("S2", "预告代替内容", "检查是否可以直接进入正文", text, NR)
            if (sentence_starts(text, "值得注意的是") || sentence_starts(text, "需要强调的是") || sentence_starts(text, "需要指出的是") || sentence_starts(text, "从某种意义上说"))
                add("L1", "空泛转场", "检查该表达是否承担了真实逻辑关系", text, NR)
            if (sentence_starts(text, "本质上") || sentence_starts(text, "真正的问题是") || sentence_starts(text, "真正的问题在于") || sentence_starts(text, "更深层次看") || sentence_starts(text, "更深层次来看"))
                add("L2", "假装深入", "检查后文是否增加了新的事实或推理", text, NR)
            if (text ~ /(不是.*而是|并非.*而是|不在于.*而在于|不只(是)?.*(更是|还是))/)
                add("L9", "否定揭晓句", "该句式不是禁用项，只检查是否反复制造假冲突", text, NR)
            if (text ~ /(颠覆性|革命性|前所未有|赋能|抓手|闭环|底层逻辑|顶层设计|全链路|组合拳)/)
                add("L10", "营销或抽象词", "单个词不能证明问题，检查是否缺少主体、动作和后果", text, NR)
        }
        END {
            flush_paragraph()
            if (paragraph_count >= 10) {
                one_sentence = 0
                for (i = 1; i <= paragraph_count; i++)
                    if (paragraph_sentences[i] <= 1) one_sentence++
                ratio = one_sentence / paragraph_count
                if (ratio >= 0.75)
                    add("R2", "段落形状单一", sprintf("可识别段落中有 %.0f%% 只有一句；移动端排版合理时保留", ratio * 100), paragraph_text[1], paragraph_line[1])
            }
            if (paragraph_count >= 8) {
                minimum = paragraph_length[1]
                maximum = paragraph_length[1]
                total = 0
                for (i = 1; i <= paragraph_count; i++) {
                    if (paragraph_length[i] < minimum) minimum = paragraph_length[i]
                    if (paragraph_length[i] > maximum) maximum = paragraph_length[i]
                    total += paragraph_length[i]
                }
                average = total / paragraph_count
                if (average >= 20 && (maximum - minimum) / average <= 0.45)
                    add("R2", "段长过度一致", "多个段落长度接近，检查是否按同一模具展开", paragraph_count " 段，字符数范围 " minimum "-" maximum, paragraph_line[1])
            }
            for (i = 1; i <= opener_total; i++) {
                opener = openers[i]
                if (opener_count[opener] >= 3)
                    add("R6", "重复段首", "“" opener "”作为段首出现 " opener_count[opener] " 次，检查是否形成固定路标", opener, opener_line[opener])
            }

            printf "可见字符 %d，可识别段落 %d\n", visible_count, paragraph_count
            if (finding_count > 0) {
                printf "发现 %d 个候选问题，全部需要结合声纹和语境人工判断：\n", finding_count
                for (i = 1; i <= finding_count; i++)
                    printf "- 第 %d 行 [%s %s] %s；“%s”\n", finding_line[i], finding_code[i], finding_label[i], finding_reason[i], finding_value[i]
            } else {
                print "未发现本检查器覆盖的文字形状。"
            }
            print "检查器不判断材料充足度、语义推进、作者身份或风格一致性，也不自动修改正文。"
        }
    ' "$@"
}

self_test() {
    sample_output=$(printf '%s\n' \
        '在当今时代，内容创作正在发生变化。' '' \
        '接下来我们将深入分析这个问题。' '' \
        '值得注意的是，这不是工具变化，而是认知革命。' '' \
        '一句话。' '' '很重要。' '' '必须重视。' '' '值得思考。' | run_check -) || exit 2
    for code in S1 S2 L1 L9 R5; do
        printf '%s\n' "$sample_output" | grep -F "[$code " >/dev/null || fail "Self-test missing $code."
    done
    masked_output=$(printf '%s\n' \
        '正文直接说明已经确认的事实。' '' \
        '> 在当今时代，值得注意的是。' '' \
        '```text' '接下来我们将深入分析。' '```' | run_check -) || exit 2
    printf '%s\n' "$masked_output" | grep -F '发现 ' >/dev/null && fail 'Self-test masking failed.'
    printf 'self-test passed\n'
}

PATH_ARG=${1-}
[ -n "$PATH_ARG" ] || fail 'Missing Markdown or text path.'

if [ "$PATH_ARG" = 'self-test' ]; then
    self_test
    exit 0
fi

if [ "$PATH_ARG" != '-' ] && [ ! -f "$PATH_ARG" ]; then
    fail "File not found: $PATH_ARG"
fi

run_check "$PATH_ARG"
