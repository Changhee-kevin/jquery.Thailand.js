# Flutter AI Chat (Mockup)

간단한 AI 채팅 UI 목업입니다. HTML 버전(`/ai-chat-mockup.html`)과 동일한 기능을 Flutter로 구현했습니다.

## 기능

- 사용자/AI 말풍선 (좌·우 정렬, 시간 표시)
- 이미지·파일 첨부 (다중 선택, 전송 전 미리보기/취소)
- AI 응답에 이미지(탭하여 확대) / 다운로드 가능한 파일 카드
- 타이핑 인디케이터
- 새 대화 시작 버튼

## 실행 방법

```bash
# 1) Flutter 프로젝트 골격 생성 (android/ios/web 폴더 자동 생성)
cd flutter_ai_chat
flutter create .

# 2) 의존성 설치
flutter pub get

# 3) 실행 (연결된 디바이스/에뮬레이터에서)
flutter run
```

> `flutter create .` 명령은 기존 `lib/main.dart`와 `pubspec.yaml`은 덮어쓰지 않고,
> 플랫폼별 폴더(`android/`, `ios/`, `web/` 등)만 생성합니다.

## 실제 AI 엔진 연동

`lib/main.dart`의 `_mockAiReply()` 함수를 실제 API 호출로 교체하세요.
응답에서 받은 텍스트/이미지 URL/파일 바이트를 `Attachment` 객체로 감싸
`_messages`에 추가하면 됩니다.

## 사용 패키지

- `file_picker` — 로컬 파일/이미지 선택
- `path_provider` — 다운로드 파일 저장 경로
