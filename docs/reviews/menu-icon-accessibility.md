# R188 · 다른 앱의 메뉴 아이콘을 자동으로 읽을 수 있는가

2026-10-15. 사용자가 음악 앱의 보기 메뉴에서 보이는 아이콘을 예로 들어 Claude의 “자동으로 못 가져온다”는 설명을 확인해 달라고 요청했다. 기능 구현 요청이 아니며 현재 UI/버전은 변경하지 않는다.

> 후속 R189–R190에서 실제 Music 메뉴 리소스 연결을 읽어 공개 심볼6개를 검증했다. 아래는 R188 당시 조사 기록이며 이후 구현은 [메뉴 리소스 아이콘](menu-resource-icons.md)에 정리한다.

## 결론과 범위

**Tile Launcher가 현재 쓰는 공개 접근성 API에서 다른 앱의 메뉴 이미지 원본이나 SF Symbol 이름을 범용적으로 읽는 표준 속성이 없다는 설명은 맞다.** 모든 앱·모든 우회 방법에서 절대 불가능하다는 뜻은 아니다. 음악 앱 자체의 특수 속성이나 리소스별 추출 가능성까지 확인한 결론으로 확대하지 않는다.

## 확인한 내용

1. Apple의 `NSMenuItem.image`는 메뉴 항목이 가진 NSImage를 읽고 쓰는 AppKit 속성이다. 해당 앱 내부의 실제 NSMenuItem에 접근할 때 사용한다. 다른 프로세스의 메뉴를 AXUIElement로 받은 것만으로 그 객체의 image 속성에 접근할 수 있다는 뜻은 아니다.
2. 설치된 Xcode-beta/macOS27.2 SDK의 AXAttributeConstants.h와 NSAccessibilityConstants.h를 확인했다. 공개 메뉴 속성은 단축키 문자/가상키/글리프/수정자·체크 문자·기본 UI 요소 등을 제공하지만 메뉴 이미지 데이터/리소스 이름/SF Symbol 이름을 반환하는 표준 속성은 없었다. NSAccessibilityImage는 이미지 역할과 설명을 제공하는 프로토콜이며 원본 파일/심볼 이름을 넘기는 API는 아니다.
3. `AXMenuItemCmdGlyph`는 메뉴 왼쪽 아이콘이 아니라 Delete 같은 키의 단축키 표시 기호다. 이름에Glyph가 있다는 이유로 메뉴 이미지를 얻는 속성으로 사용하면 안 된다.
4. 이미지를 지정한 실제 NSMenuItem을 별도 임시 프로세스에 만들고, 화면에 표시하지 않은 채 AppKit 접근성 속성을 열거했다. image는존재하지만image/icon/symbol 속성은0개, 하위 접근성 요소도0개였다. 해당 이미지의 NSImage.name도nil이었다. 선택한SF Symbol을 설정할 때의 이름이 NSImage.name으로 항상 되돌아오는 것도 아니다.
5. 실행 중인 음악 앱은 이 Mac에서0개였다. 앱을 열거나 메뉴를 조작하지 않았으므로 **스크린샷 속 Music 메뉴의 런타임 AX 속성은 직접 확인하지 않았다.** 진단 프로세스의 AXIsProcessTrusted는true였으며 이번 한계는 대상 앱 미실행이다.
6. 설치된 Music1.7.2에는 MainMenu.nib/Assets.car가 있다. MainMenu.nib의NIBArchive 안에서 해당 메뉴 제목은 확인했지만, 표준 파일 API로 메뉴 경로→그림을 자동 연결하는 기능을 확인한 것은 아니다. Music의 scripting dictionary에도 메뉴 아이콘을 제공하는 메뉴 항목 모델은 없었다.

## 합성 NSMenuItem 결과

```
image exists: true
image name: nil
AX trusted: true
running Music instances: 0
AX attributes: AXChildren, AXEnabled, AXFrame, AXMenuItemCmdChar,
  AXMenuItemCmdGlyph, AXMenuItemCmdModifiers, AXMenuItemCmdVirtualKey,
  AXMenuItemMarkChar, AXMenuItemPrimaryUIElement, AXParent, AXPosition,
  AXRole, AXSelected, AXServesAsTitleForUIElements, AXSize, AXSubrole,
  AXTitle, AXTopLevelUIElement
image/icon/symbol named attributes: []
children: 0
```

이는 표준 AppKit 메뉴의 내부 접근성 표현을 확인한 실험이며 Music 자체의 전체/비공개 속성을 검증한 결과는 아니다. 코드/로그는 `/tmp/tile-menu-icon-research/menu-image.swift`, `result.log`다.

## 우회 방법과 제품 판단

- 앱별 리소스 분석: 정적인 nib/asset의 이미지를 읽어 메뉴와 연결하는 전용 처리를 시도할 수 있다. 동적 메뉴, 런타임 지정 이미지, 앱 업데이트·언어 차이 때문에 범용 자동 획득을 보장할 수 없다. Music용 추출 성공을 주장하지 않는다.
- 화면 캡처: 열린 메뉴의 아이콘 영역을 잘라 쓰는 방식은 가능하지만 화면 접근과 메뉴 표시가 필요하고 배경·해상도·테마·비활성화 색이 섞인다. 원본 벡터/심볼 이름을 반환하는 API와 다르다. 이번에는 캡처하지 않았다.
- 현재의 SF Symbol 기본값/사용자 지정은 UI를 건드리지 않고 안정적으로 표시하는 대안이다. 앱 원본에서 자동 추출한 것으로 설명하지 않는다. UI·제품 코드를 바꾸거나 새 패키지를 만들지 않았다.

## Apple 공식 근거

- [NSMenuItem.image](https://developer.apple.com/documentation/appkit/nsmenuitem/image)
- [AXUIElementCopyAttributeNames](https://developer.apple.com/documentation/applicationservices/1459475-axuielementcopyattributenames)
- [NSAccessibilityImage](https://developer.apple.com/documentation/appkit/nsaccessibilityimage)
- [AXMenuItemCmdGlyph](https://developer.apple.com/documentation/applicationservices/kaxmenuitemcmdglyphattribute)

공개 SDK에 표준 이미지 속성이 없다는 판단에는 설치된 헤더와 합성 메뉴 실험을 함께 사용했다. NSMenuItem의preferredImageVisibility는 이미지를 그릴지 정하는 속성이며 다른 앱에 이미지를 제공하는 전송 API는 아니다.
