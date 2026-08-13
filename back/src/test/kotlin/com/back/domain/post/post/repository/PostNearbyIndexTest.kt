package com.back.domain.post.post.repository

import jakarta.persistence.EntityManager
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.context.ActiveProfiles
import org.springframework.transaction.annotation.Transactional

/**
 * 인덱스 "계약" 테스트.
 *
 * 기능이 맞게 동작하는지(=결과가 옳은지)는 컨트롤러 테스트가 본다.
 * 여기서는 그 기능이 **인덱스를 타고** 동작하는지를 못박는다.
 * 인덱스를 실수로 지우거나, 조건을 인덱스가 못 타는 형태로 바꾸면 이 테스트가 깨진다.
 */
@ActiveProfiles("test")
@SpringBootTest
@Transactional
class PostNearbyIndexTest {
    @Autowired
    private lateinit var em: EntityManager

    @Test
    @DisplayName("주변 검색은 Seq Scan 이 아니라 공간 인덱스를 탄다")
    fun t1() {
        // 플래너가 인덱스를 고르려면 데이터가 어느 정도 있어야 한다.
        // (몇 건뿐이면 통째로 읽는 Seq Scan 이 더 싸므로 인덱스를 안 쓴다)
        em.createNativeQuery(
            """
            INSERT INTO post (create_date, modify_date, author_id, title, body_id, location)
            SELECT now(), now(),
                   (SELECT author_id FROM post WHERE author_id IS NOT NULL LIMIT 1),
                   'bulk ' || g,
                   NULL,
                   ST_MakePoint(126.5 + random(), 37.0 + random())::geography
            FROM generate_series(1, 3000) g
            """
        ).executeUpdate()

        em.createNativeQuery("ANALYZE post").executeUpdate()

        val plan = explain(
            """
            SELECT id FROM post
            WHERE location IS NOT NULL
              AND ST_DWithin(location, ST_MakePoint(127.0276, 37.4979)::geography, 3000)
            """
        )

        assertThat(plan)
            .`as`("실행계획:\n%s", plan)
            .containsIgnoringCase("Index Scan")
        assertThat(plan)
            .`as`("실행계획:\n%s", plan)
            .doesNotContainIgnoringCase("Seq Scan on post")
    }

    @Suppress("UNCHECKED_CAST")
    private fun explain(sql: String): String =
        (em.createNativeQuery("EXPLAIN (ANALYZE, BUFFERS) $sql").resultList as List<Any>)
            .joinToString("\n") { it.toString() }
}
