package com.back.domain.post.post.service

import com.back.domain.post.postUser.service.PostUserService
import com.back.standard.extensions.getOrThrow
import jakarta.persistence.EntityManager
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.springframework.ai.embedding.EmbeddingModel
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.context.ActiveProfiles
import org.springframework.transaction.annotation.Transactional

/**
 * 임베딩 = 문장을 숫자 배열(벡터)로 바꾸는 것.
 *
 * 외부 API 키 없이, yaml 에 적어둔 허깅페이스 ONNX 모델을 내려받아 **로컬에서** 계산한다.
 * 그래서 CI 에서도, 인터넷이 끊긴 운영 서버에서도(한 번 받아두면) 돌아간다.
 */
@ActiveProfiles("test")
@SpringBootTest
@Transactional
class PostEmbeddingTest {
    @Autowired
    private lateinit var embeddingModel: EmbeddingModel

    @Autowired
    private lateinit var postService: PostService

    @Autowired
    private lateinit var postUserService: PostUserService

    @Autowired
    private lateinit var em: EntityManager

    @Test
    @DisplayName("임베딩 모델은 한국어 문장을 384차원 벡터로 만든다")
    fun t1() {
        val v = embeddingModel.embed("김치찌개가 맛있는 집")

        assertThat(v).hasSize(384)
        // 전부 0 이면 모델이 제대로 안 돌아간 것
        assertThat(v.any { it != 0.0f }).isTrue()
    }

    @Test
    @DisplayName("임베딩은 의미가 가까운 문장끼리 더 비슷하다")
    fun t2() {
        val base = embeddingModel.embed("김치찌개가 맛있는 집")
        val similar = embeddingModel.embed("돼지고기 김치찜을 잘하는 식당")
        val different = embeddingModel.embed("주식 투자로 손실을 줄이는 방법")

        assertThat(cosine(base, similar))
            .`as`("비슷한 문장(%f) 이 다른 문장(%f) 보다 가까워야 한다", cosine(base, similar), cosine(base, different))
            .isGreaterThan(cosine(base, different))
    }

    @Test
    @DisplayName("글을 쓰면 임베딩이 자동으로 저장된다")
    fun t3() {
        val author = postUserService.findByUsername("user1").getOrThrow()
        val post = postService.write(author, "김치찌개 맛집", "묵은지로 끓인 김치찌개")
        em.flush()

        assertThat(post.embedding).isNotNull()
        assertThat(post.embedding!!.size).isEqualTo(384)
    }

    private fun cosine(a: FloatArray, b: FloatArray): Double {
        var dot = 0.0; var na = 0.0; var nb = 0.0
        for (i in a.indices) {
            dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]
        }
        return dot / (Math.sqrt(na) * Math.sqrt(nb))
    }
}
