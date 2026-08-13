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
 * 벡터(의미) 검색.
 *
 * 전문검색은 "그 단어가 들어있는 글"을 찾는다. 벡터검색은 "뜻이 비슷한 글"을 찾는다.
 * 그래서 검색어에 없는 단어로 쓰인 글도 걸린다 — 이 차이를 t1 이 못박는다.
 */
@ActiveProfiles("test")
@SpringBootTest
@Transactional
class PostVectorSearchTest {
    @Autowired
    private lateinit var postRepository: PostRepository

    @Autowired
    private lateinit var postService: PostService

    @Autowired
    private lateinit var postUserService: PostUserService

    @Autowired
    private lateinit var em: EntityManager

    @Test
    @DisplayName("벡터검색, 단어가 겹치지 않아도 뜻이 비슷하면 걸린다")
    fun t1() {
        val author = postUserService.findByUsername("user1").getOrThrow()
        postService.write(author, "돼지고기 김치찜 잘하는 식당", "묵은지와 삼겹살을 푹 끓였다")
        postService.write(author, "주식 투자 손실 줄이기", "분산투자와 손절 원칙에 대하여")
        em.flush()

        // "김치찌개 맛집" 이라는 단어는 위 두 글 어디에도 그대로 들어있지 않다
        val page = postRepository.findQPagedBySimilarity("김치찌개 맛집", PageRequest.of(0, 2))

        assertThat(page.content).isNotEmpty()
        assertThat(page.content.first().title)
            .`as`("의미가 가까운 음식 글이 1위여야 한다")
            .isEqualTo("돼지고기 김치찜 잘하는 식당")
    }

    @Test
    @DisplayName("벡터검색은 HNSW 인덱스를 탄다")
    fun t2() {
        em.createNativeQuery(
            """
            INSERT INTO post (create_date, modify_date, author_id, title, body_id, embedding)
            SELECT now(), now(),
                   (SELECT author_id FROM post WHERE author_id IS NOT NULL LIMIT 1),
                   '잡글 ' || g,
                   NULL,
                   (SELECT array_agg(random())::real[]::vector FROM generate_series(1, 384))
            FROM generate_series(1, 3000) g
            """
        ).executeUpdate()
        em.createNativeQuery("ANALYZE post").executeUpdate()

        val zeros = (1..384).joinToString(",") { "0.1" }
        val plan = explain(
            "SELECT id FROM post WHERE embedding IS NOT NULL ORDER BY embedding <=> '[$zeros]'::vector LIMIT 5"
        )

        assertThat(plan)
            .`as`("실행계획:\n%s", plan)
            .containsIgnoringCase("idx_post_embedding_hnsw")
    }

    @Suppress("UNCHECKED_CAST")
    private fun explain(sql: String): String =
        (em.createNativeQuery("EXPLAIN (ANALYZE, BUFFERS) $sql").resultList as List<Any>)
            .joinToString("\n") { it.toString() }
}
