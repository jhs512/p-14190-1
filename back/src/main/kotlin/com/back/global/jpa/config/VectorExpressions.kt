package com.back.global.jpa.config

import com.querydsl.core.types.Expression
import com.querydsl.core.types.dsl.Expressions
import com.querydsl.core.types.dsl.NumberExpression

/**
 * pgvector 연산을 QueryDSL 에서 부르기 위한 헬퍼.
 *
 * Hibernate 의 hibernate-vector 모듈이 `cosine_distance` 같은 함수를 등록해 두므로
 * 네이티브 쿼리 없이 `function('cosine_distance', ...)` 로 호출할 수 있다.
 */
object VectorExpressions {

    /**
     * 코사인 거리 (0 에 가까울수록 비슷하다).
     *
     * pgvector 의 `<=>` 연산자와 같다. ORDER BY 에 이 값을 쓰면 HNSW 인덱스가 동작한다.
     */
    fun cosineDistance(column: Expression<*>, target: FloatArray): NumberExpression<Double> =
        Expressions.numberTemplate(
            Double::class.java,
            "function('cosine_distance', {0}, {1})",
            column,
            target
        )
}
