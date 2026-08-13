package com.back.global.pGroonga.annotation

/**
 * 이 엔티티의 테이블에 PGroonga 복합 표현식 인덱스를 만든다.
 *
 * 예) @PGroongaIndex(columns = ["title", "content"])
 *   → CREATE INDEX ... USING pgroonga ((ARRAY["title"::text, "content"::text]))
 */
@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.RUNTIME)
@Repeatable
annotation class PGroongaIndex(
    val columns: Array<String>,
    // TokenBigram = 2글자 단위 N-gram. 한국어처럼 띄어쓰기로 단어를 못 나누는 언어에 적합
    val tokenizer: String = "TokenBigram",
)
