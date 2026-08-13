package com.back.global.jpa.config

import com.querydsl.core.types.dsl.BooleanExpression
import com.querydsl.core.types.dsl.Expressions
import com.querydsl.core.types.dsl.NumberExpression
import com.querydsl.core.types.dsl.SimpleExpression

/**
 * PostGIS 함수를 QueryDSL 에서 부르기 위한 헬퍼.
 *
 * 네이티브 쿼리를 쓰지 않고, Hibernate 가 이미 알고 있는 공간 함수(hibernate-spatial 이 등록)를
 * `function('...')` 문법으로 호출한다. 덕분에 페이징·정렬·조건 결합을 전부 QueryDSL 로 유지할 수 있다.
 */
object SpatialFunctions {

    /**
     * 반경 안에 있는가. `ST_DWithin(location, POINT, 미터)`
     *
     * geography 타입이므로 세 번째 인자의 단위가 곧 "미터"다.
     * 이 조건은 GIST 인덱스를 탈 수 있는 형태라, 반경이 좁을수록 Bitmap Index Scan 으로 빠르게 걸러진다.
     */
    fun dWithin(location: SimpleExpression<*>, lng: Double, lat: Double, radiusM: Double): BooleanExpression =
        Expressions.booleanTemplate(
            "function('st_dwithin', {0}, function('st_makepoint', {1}, {2}), {3}) = true",
            location, lng, lat, radiusM
        )

    /**
     * 두 점 사이의 거리(미터). `ST_Distance(location, POINT)`
     *
     * 정렬용으로 쓴다. 인덱스로 후보를 좁힌 뒤(dWithin) 그 안에서만 정확한 거리를 계산하는 것이 핵심이다.
     */
    fun distanceM(location: SimpleExpression<*>, lng: Double, lat: Double): NumberExpression<Double> =
        Expressions.numberTemplate(
            Double::class.java,
            "function('st_distance', {0}, function('st_makepoint', {1}, {2}))",
            location, lng, lat
        )
}
