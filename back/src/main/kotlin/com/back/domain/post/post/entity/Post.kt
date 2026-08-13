package com.back.domain.post.post.entity

import com.back.domain.post.postComment.entity.PostComment
import com.back.domain.post.postUser.entity.PostUser
import com.back.global.exception.ServiceException
import com.back.global.jpa.entity.BaseTime
import com.back.global.pGroonga.annotation.PGroongaIndex
import jakarta.persistence.CascadeType.PERSIST
import jakarta.persistence.CascadeType.REMOVE
import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.FetchType.LAZY
import jakarta.persistence.ManyToOne
import jakarta.persistence.OneToMany
import jakarta.persistence.OneToOne
import org.hibernate.annotations.Array
import org.hibernate.annotations.JdbcTypeCode
import org.hibernate.type.SqlTypes
import org.locationtech.jts.geom.Coordinate
import org.locationtech.jts.geom.GeometryFactory
import org.locationtech.jts.geom.Point
import org.locationtech.jts.geom.PrecisionModel

@Entity
// 제목 전문검색용 PGroonga 인덱스. 부팅 시 PGroongaIndexConfig 가 만들어준다
@PGroongaIndex(columns = ["title"])
class Post(
    @field:ManyToOne(fetch = LAZY) val author: PostUser,
    var title: String,
    content: String
) : BaseTime() {
    // 글이 가리키는 장소. geography 는 지구를 구로 계산하므로 ST_Distance 결과가 곧 "미터"다
    // (geometry 로 잡으면 4326 에서 결과가 '도(degree)' 라서 거리 계산이 어긋난다)
    @Column(columnDefinition = "geography(Point,4326)")
    var location: Point? = null

    // 경도(longitude): 동서. 위도(latitude): 남북.
    // PostGIS 는 Point(경도, 위도) 순서다 — 위경도 순으로 넣는 실수가 잦아 프로퍼티로 감싼다
    val lng: Double? get() = location?.x
    val lat: Double? get() = location?.y

    fun setLocation(lng: Double?, lat: Double?) {
        location = if (lng == null || lat == null) null else newPoint(lng, lat)
    }

    // 글 내용의 의미를 담은 벡터. 차원 수는 임베딩 모델이 정한다 (multilingual-e5-small = 384)
    @Column(columnDefinition = "vector(384)")
    @JdbcTypeCode(SqlTypes.VECTOR)
    @Array(length = 384)
    var embedding: FloatArray? = null

    @OneToOne(fetch = LAZY, cascade = [PERSIST, REMOVE])
    var body: PostBody = PostBody(content)

    @OneToMany(
        mappedBy = "post",
        cascade = [PERSIST, REMOVE],
        orphanRemoval = true
    )
    val comments: MutableList<PostComment> = mutableListOf()

    var content: String
        get() = body.content
        set(value) {
            if (body.content != value) {
                body.content = value
                updateModifyDate()
            }
        }

    fun modify(title: String, content: String) {
        this.title = title
        this.content = content
    }

    fun addComment(author: PostUser, content: String): PostComment {
        val postComment = PostComment(author, this, content)
        comments.add(postComment)

        author.incrementPostCommentsCount()

        return postComment
    }

    fun findCommentById(id: Int): PostComment? {
        return comments.find { it.id == id }
    }

    fun deleteComment(postComment: PostComment): Boolean {
        postComment.author.decrementPostCommentsCount()

        return comments.remove(postComment)
    }

    fun checkActorCanModify(actor: PostUser) {
        if (author != actor) throw ServiceException("403-1", "${id}번 글 수정 권한이 없습니다.")
    }

    fun checkActorCanDelete(actor: PostUser) {
        if (author != actor) throw ServiceException("403-2", "${id}번 글 삭제 권한이 없습니다.")
    }

    companion object {
        // SRID 4326 = WGS84, 즉 GPS 가 쓰는 그 좌표계
        private val geometryFactory = GeometryFactory(PrecisionModel(), 4326)

        fun newPoint(lng: Double, lat: Double): Point =
            geometryFactory.createPoint(Coordinate(lng, lat))
    }
}
