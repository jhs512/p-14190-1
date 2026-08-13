package com.back.global.pGroonga.config

import com.querydsl.core.types.Expression
import com.querydsl.core.types.dsl.BooleanExpression
import com.querydsl.core.types.dsl.Expressions

/**
 * QueryDSL 에서 PGroonga 전문검색을 부르기 위한 헬퍼.
 *
 * 네이티브 쿼리 없이 `ARRAY[col::text, ...] &@~ '키워드'` 를 만들어낸다.
 * 렌더링은 CustomPostgreSQLDialect 에 등록한 pgroonga_match 함수가 담당한다.
 */
object PGroongaExpressions {

    /**
     * 주어진 컬럼들에서 키워드를 전문검색한다.
     *
     * 주의: 인덱스를 타려면 여기 넘기는 컬럼 조합이
     * `@PGroongaIndex(columns = [...])` 로 만든 인덱스의 컬럼 조합과 **같아야** 한다.
     */
    fun match(kw: String, vararg columns: Expression<*>): BooleanExpression {
        require(columns.isNotEmpty()) { "전문검색 대상 컬럼이 최소 1개는 필요합니다" }

        // function('pgroonga_match', col1, ..., kw) = true
        val placeholders = (columns.indices).joinToString(", ") { "{$it}" }
        val kwPlaceholder = "{${columns.size}}"
        val args: Array<Any> = arrayOf(*columns, kw)

        return Expressions.booleanTemplate(
            "function('pgroonga_match', $placeholders, $kwPlaceholder) = true",
            *args
        )
    }
}
