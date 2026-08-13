package com.back.domain.post.post.repository

import com.back.domain.post.post.service.PostService
import com.back.domain.post.postUser.service.PostUserService
import com.back.standard.extensions.getOrThrow
import jakarta.persistence.EntityManager
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.data.domain.PageRequest
import org.springframework.test.context.ActiveProfiles
import org.springframework.transaction.annotation.Transactional

/**
 * PGroonga 한글 전문검색.
 *
 * LIKE '%키워드%' 와 다른 점:
 *  - 형태소/N-gram 으로 쪼개 색인하므로 한글이 제대로 걸린다
 *  - 인덱스를 타므로 글이 많아져도 느려지지 않는다 (인덱스 계약은 아래 t2 가 못박는다)
 */
@ActiveProfiles("test")
@SpringBootTest
@Transactional
class PostFullTextSearchTest {
    @Autowired
    private lateinit var postRepository: PostRepository

    @Autowired
    private lateinit var postService: PostService

    @Autowired
    private lateinit var postUserService: PostUserService

    @Autowired
    private lateinit var em: EntityManager

    @Test
    @DisplayName("전문검색, 한글 키워드가 제목에서 걸린다")
    fun t1() {
        val author = postUserService.findByUsername("user1").getOrThrow()
        postService.write(author, "김치찌개 맛집", "묵은지로 끓인 김치찌개")
        postService.write(author, "파스타 맛집", "크림 파스타가 맛있다")
        em.flush()

        val page = postRepository.findQPagedBySearchKw("김치찌개", PageRequest.of(0, 10))

        assertThat(page.content.map { it.title }).contains("김치찌개 맛집")
        assertThat(page.content.map { it.title }).doesNotContain("파스타 맛집")
    }

    @Test
    @DisplayName("전문검색은 Seq Scan 이 아니라 PGroonga 인덱스를 탄다")
    fun t2() {
        bulkInsert()

        val plan = explain("SELECT id FROM post WHERE ARRAY[title::text] &@~ '잡글'")

        assertThat(plan)
            .`as`("실행계획:\n%s", plan)
            .containsIgnoringCase("idx_post_title_pgroonga")
        assertThat(plan)
            .`as`("실행계획:\n%s", plan)
            .doesNotContainIgnoringCase("Seq Scan on post")
    }

    @Test
    @DisplayName("전문검색 + 주변검색을 함께 걸면 두 인덱스를 BitmapAnd 로 결합한다")
    fun t3() {
        bulkInsert()

        // 조건이 둘이면 플래너는 각 인덱스에서 "해당하는 행의 위치 비트맵"을 만들어 AND 로 겹친 뒤
        // 그 결과만 테이블에서 읽는다. 인덱스 두 개가 실제로 함께 일한다는 증거다.
        val plan = explain(
            """
            SELECT id FROM post
            WHERE ARRAY[title::text] &@~ '잡글'
              AND ST_DWithin(location, ST_MakePoint(127.0, 37.5)::geography, 5000)
            """
        )

        assertThat(plan)
            .`as`("실행계획:\n%s", plan)
            .containsIgnoringCase("BitmapAnd")
        assertThat(plan)
            .`as`("실행계획:\n%s", plan)
            .containsIgnoringCase("Bitmap Index Scan on idx_post_title_pgroonga")
        assertThat(plan)
            .`as`("실행계획:\n%s", plan)
            .containsIgnoringCase("Bitmap Index Scan on idx_post_location_gist")
    }

    private fun bulkInsert() {
        em.createNativeQuery(
            """
            INSERT INTO post (create_date, modify_date, author_id, title, body_id, location)
            SELECT now(), now(),
                   (SELECT author_id FROM post WHERE author_id IS NOT NULL LIMIT 1),
                   '잡글 ' || g,
                   NULL,
                   ST_MakePoint(126.5 + random(), 37.0 + random())::geography
            FROM generate_series(1, 3000) g
            """
        ).executeUpdate()
        em.createNativeQuery("ANALYZE post").executeUpdate()
    }

    @Suppress("UNCHECKED_CAST")
    private fun explain(sql: String): String =
        (em.createNativeQuery("EXPLAIN (ANALYZE, BUFFERS) $sql").resultList as List<Any>)
            .joinToString("\n") { it.toString() }
}
