const fs = require('fs');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const {
  doc,
  deleteDoc,
  getDoc,
  setDoc,
  setLogLevel,
  updateDoc,
  serverTimestamp,
  writeBatch,
  deleteField,
} = require('firebase/firestore');

const PROJECT_ID = 'sunrin-app-public-test';
const FIRESTORE_HOST = '127.0.0.1';
const FIRESTORE_PORT = 8080;

const fixedDate = new Date('2026-04-18T00:00:00.000Z');

function eventPayload(overrides = {}) {
  return {
    title: '중간 점검',
    category: 'notice',
    startDate: fixedDate,
    endDate: fixedDate,
    classId: 'personal',
    createdBy: 'alice',
    memberIds: ['alice'],
    lastEditedBy: 'alice',
    lastEditedAt: serverTimestamp(),
    ...overrides,
  };
}

function timetableOverridePayload(overrides = {}) {
  return {
    date: '20260418',
    periods: {
      1: {
        subject: '수학 심화',
        originalSubject: '수학',
        updatedAt: serverTimestamp(),
      },
    },
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

async function main() {
  setLogLevel('silent');
  const rules = fs.readFileSync('firestore.rules', 'utf8');
  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules,
      host: FIRESTORE_HOST,
      port: FIRESTORE_PORT,
    },
  });

  const results = [];

  async function runCase(name, runner) {
    try {
      await runner();
      results.push({ name, status: 'PASS' });
      console.log(`PASS ${name}`);
    } catch (error) {
      results.push({ name, status: 'FAIL', error });
      console.error(`FAIL ${name}`);
      console.error(error);
    }
  }

  try {
    await testEnv.clearFirestore();

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();

      await setDoc(doc(db, 'classes', 'solo-class'), {
        name: '개인반',
        inviteCode: 'ABC123',
        createdBy: 'alice',
        memberIds: ['alice'],
        memberNames: { alice: 'Alice' },
        colorValue: 0xff4285f4,
        createdAt: fixedDate,
      });

      await setDoc(doc(db, 'classes', 'shared-class'), {
        name: '공유반',
        inviteCode: 'BCD234',
        createdBy: 'alice',
        memberIds: ['alice', 'bob'],
        memberNames: { alice: 'Alice', bob: 'Bob' },
        colorValue: 0xff34a853,
        createdAt: fixedDate,
      });

      await setDoc(doc(db, 'classInvites', 'ABC123'), {
        code: 'ABC123',
        classId: 'solo-class',
        className: '개인반',
        createdBy: 'alice',
        createdAt: fixedDate,
      });

      await setDoc(doc(db, 'classInvites', 'BCD234'), {
        code: 'BCD234',
        classId: 'shared-class',
        className: '공유반',
        createdBy: 'alice',
        createdAt: fixedDate,
      });
    });

    const aliceDb = testEnv.authenticatedContext('alice').firestore();
    const bobDb = testEnv.authenticatedContext('bob').firestore();
    const malloryDb = testEnv.authenticatedContext('mallory').firestore();
    const anonDb = testEnv.unauthenticatedContext().firestore();

    await runCase('학급 멤버는 자신의 학급 문서를 읽을 수 있다', async () => {
      await assertSucceeds(getDoc(doc(aliceDb, 'classes', 'solo-class')));
    });

    await runCase('학급 멤버가 아닌 사용자는 다른 학급 문서를 읽을 수 없다', async () => {
      await assertFails(getDoc(doc(bobDb, 'classes', 'solo-class')));
    });

    await runCase('비멤버도 초대 코드 조회용 최소 문서는 읽을 수 있다', async () => {
      await assertSucceeds(getDoc(doc(bobDb, 'classInvites', 'ABC123')));
    });

    await runCase('학급과 초대 문서는 같은 배치에서 생성할 수 있다', async () => {
      const batch = writeBatch(aliceDb);
      batch.set(doc(aliceDb, 'classes', 'new-class'), {
        name: '새 학급',
        inviteCode: 'EFG345',
        createdBy: 'alice',
        memberIds: ['alice'],
        memberNames: { alice: 'Alice' },
        colorValue: 0xffea4335,
        createdAt: serverTimestamp(),
      });
      batch.set(doc(aliceDb, 'classInvites', 'EFG345'), {
        code: 'EFG345',
        classId: 'new-class',
        className: '새 학급',
        createdBy: 'alice',
        createdAt: serverTimestamp(),
      });
      await assertSucceeds(batch.commit());
    });

    await runCase('기존 초대 코드 문서는 덮어쓸 수 없다', async () => {
      await assertFails(
        setDoc(doc(aliceDb, 'classInvites', 'ABC123'), {
          code: 'ABC123',
          classId: 'other-class',
          className: '다른 학급',
          createdBy: 'alice',
          createdAt: serverTimestamp(),
        }),
      );
    });

    await runCase('초대 코드 참여 시 자기 자신만 memberIds에 추가할 수 있다', async () => {
      await assertSucceeds(
        updateDoc(doc(bobDb, 'classes', 'solo-class'), {
          memberIds: ['alice', 'bob'],
          'memberNames.bob': 'Bob',
        }),
      );
    });

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, 'classes', 'solo-class'), {
        name: '개인반',
        inviteCode: 'ABC123',
        createdBy: 'alice',
        memberIds: ['alice'],
        memberNames: { alice: 'Alice' },
        colorValue: 0xff4285f4,
        createdAt: fixedDate,
      });
    });

    await runCase('초대 코드 참여 요청으로 다른 uid를 함께 추가하면 거부된다', async () => {
      await assertFails(
        updateDoc(doc(bobDb, 'classes', 'solo-class'), {
          memberIds: ['alice', 'bob', 'mallory'],
          'memberNames.bob': 'Bob',
          'memberNames.mallory': 'Mallory',
        }),
      );
    });

    await runCase('일반 멤버는 나갈 수 있고 방장은 멤버가 남아 있으면 나갈 수 없다', async () => {
      await assertSucceeds(
        updateDoc(doc(bobDb, 'classes', 'shared-class'), {
          memberIds: ['alice'],
          'memberNames.bob': deleteField(),
        }),
      );

      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await setDoc(doc(db, 'classes', 'shared-class'), {
          name: '공유반',
          inviteCode: 'BCD234',
          createdBy: 'alice',
          memberIds: ['alice', 'bob'],
          memberNames: { alice: 'Alice', bob: 'Bob' },
          colorValue: 0xff34a853,
          createdAt: fixedDate,
        });
      });

      await assertFails(
        updateDoc(doc(aliceDb, 'classes', 'shared-class'), {
          memberIds: ['bob'],
          'memberNames.alice': deleteField(),
        }),
      );
    });

    await runCase('방장은 학급 색상을 바꿀 수 있고 일반 멤버는 바꿀 수 없다', async () => {
      await assertSucceeds(
        updateDoc(doc(aliceDb, 'classes', 'shared-class'), {
          colorValue: 0xff00bcd4,
        }),
      );

      await assertFails(
        updateDoc(doc(bobDb, 'classes', 'shared-class'), {
          colorValue: 0xffff5722,
        }),
      );
    });

    await runCase('개인 일정은 본인 전용 memberIds로만 생성할 수 있다', async () => {
      await assertSucceeds(
        setDoc(doc(aliceDb, 'events', 'personal-ok'), eventPayload()),
      );
    });

    await runCase('개인 일정에 다른 사용자를 memberIds에 넣으면 거부된다', async () => {
      await assertFails(
        setDoc(
          doc(aliceDb, 'events', 'personal-bad'),
          eventPayload({ memberIds: ['alice', 'bob'] }),
        ),
      );
    });

    await runCase('개인 일정은 작성자만 수정할 수 있다', async () => {
      await assertSucceeds(
        updateDoc(doc(aliceDb, 'events', 'personal-ok'), {
          title: '개인 일정 수정',
          lastEditedBy: 'alice',
          lastEditedAt: serverTimestamp(),
        }),
      );

      await assertFails(
        updateDoc(doc(bobDb, 'events', 'personal-ok'), {
          title: '타인 개인 일정 수정',
          lastEditedBy: 'bob',
          lastEditedAt: serverTimestamp(),
        }),
      );
    });

    await runCase('학급 일정은 현재 학급 멤버 스냅샷과 일치할 때만 생성된다', async () => {
      await assertSucceeds(
        setDoc(
          doc(bobDb, 'events', 'group-ok'),
          eventPayload({
            classId: 'shared-class',
            createdBy: 'bob',
            memberIds: ['alice', 'bob'],
            lastEditedBy: 'bob',
          }),
        ),
      );
    });

    await runCase('학급 일정의 memberIds가 실제 학급 스냅샷과 다르면 거부된다', async () => {
      await assertFails(
        setDoc(
          doc(bobDb, 'events', 'group-bad'),
          eventPayload({
            classId: 'shared-class',
            createdBy: 'bob',
            memberIds: ['bob'],
            lastEditedBy: 'bob',
          }),
        ),
      );
    });

    await runCase('학급 일정은 학급 멤버가 수정할 수 있고 비멤버는 수정할 수 없다', async () => {
      await assertSucceeds(
        updateDoc(doc(aliceDb, 'events', 'group-ok'), {
          title: '학급 일정 수정',
          lastEditedBy: 'alice',
          lastEditedAt: serverTimestamp(),
        }),
      );

      await assertFails(
        updateDoc(doc(malloryDb, 'events', 'group-ok'), {
          title: '비멤버 학급 일정 수정',
          lastEditedBy: 'mallory',
          lastEditedAt: serverTimestamp(),
        }),
      );
    });

    await runCase('일정 삭제는 개인 작성자 또는 학급 멤버만 할 수 있다', async () => {
      await assertFails(deleteDoc(doc(bobDb, 'events', 'personal-ok')));
      await assertSucceeds(deleteDoc(doc(aliceDb, 'events', 'personal-ok')));

      await assertFails(deleteDoc(doc(malloryDb, 'events', 'group-ok')));
      await assertSucceeds(deleteDoc(doc(bobDb, 'events', 'group-ok')));
    });

    await runCase('알림 문서는 본인 userId로만 생성할 수 있다', async () => {
      await assertSucceeds(
        setDoc(doc(bobDb, 'notifications', 'notice-ok'), {
          userId: 'bob',
          eventId: 'group-ok',
          scheduledAt: fixedDate,
          type: 'D-1',
          sent: false,
        }),
      );
    });

    await runCase('알림 문서에 다른 userId를 넣어 생성하면 거부된다', async () => {
      await assertFails(
        setDoc(doc(malloryDb, 'notifications', 'notice-bad'), {
          userId: 'alice',
          eventId: 'group-ok',
          scheduledAt: fixedDate,
          type: 'D-1',
          sent: false,
        }),
      );
    });

    await runCase('시간표 override는 본인 하위 컬렉션에만 생성할 수 있다', async () => {
      await assertSucceeds(
        setDoc(
          doc(aliceDb, 'users', 'alice', 'timetableOverrides', '20260418'),
          timetableOverridePayload(),
        ),
      );

      await assertFails(
        setDoc(
          doc(bobDb, 'users', 'alice', 'timetableOverrides', '20260419'),
          timetableOverridePayload({ date: '20260419' }),
        ),
      );

      await assertFails(
        setDoc(
          doc(anonDb, 'users', 'alice', 'timetableOverrides', '20260420'),
          timetableOverridePayload({ date: '20260420' }),
        ),
      );
    });

    await runCase('시간표 override는 소유자만 읽을 수 있다', async () => {
      await assertSucceeds(
        getDoc(doc(aliceDb, 'users', 'alice', 'timetableOverrides', '20260418')),
      );

      await assertFails(
        getDoc(doc(bobDb, 'users', 'alice', 'timetableOverrides', '20260418')),
      );
    });

    await runCase('시간표 override는 같은 날짜 문서와 허용된 period만 저장한다', async () => {
      await assertFails(
        setDoc(
          doc(aliceDb, 'users', 'alice', 'timetableOverrides', '20260421'),
          timetableOverridePayload({ date: '20260420' }),
        ),
      );

      await assertFails(
        setDoc(
          doc(aliceDb, 'users', 'alice', 'timetableOverrides', '20260421'),
          timetableOverridePayload({
            date: '20260421',
            periods: {
              13: {
                subject: '방과후',
                updatedAt: serverTimestamp(),
              },
            },
          }),
        ),
      );
    });

    await runCase('시간표 override는 period 추가와 reset을 지원한다', async () => {
      await assertSucceeds(
        updateDoc(
          doc(aliceDb, 'users', 'alice', 'timetableOverrides', '20260418'),
          {
            'periods.2': {
              subject: '창체',
              originalSubject: '자율',
              updatedAt: serverTimestamp(),
            },
            updatedAt: serverTimestamp(),
          },
        ),
      );

      await assertSucceeds(
        updateDoc(
          doc(aliceDb, 'users', 'alice', 'timetableOverrides', '20260418'),
          {
            'periods.1': deleteField(),
            updatedAt: serverTimestamp(),
          },
        ),
      );

      await assertSucceeds(
        deleteDoc(
          doc(aliceDb, 'users', 'alice', 'timetableOverrides', '20260418'),
        ),
      );
    });

    await runCase('시간표 override는 점 경로 merge set을 허용하지 않는다', async () => {
      await assertFails(
        setDoc(
          doc(aliceDb, 'users', 'alice', 'timetableOverrides', '20260422'),
          {
            date: '20260422',
            updatedAt: serverTimestamp(),
            'periods.1': {
              subject: 'QA_SUBJECT',
              originalSubject: '재량휴업일',
              updatedAt: serverTimestamp(),
            },
          },
          { merge: true },
        ),
      );
    });
  } finally {
    await testEnv.cleanup();
  }

  const failed = results.filter((result) => result.status === 'FAIL');
  console.log(`\n${results.length - failed.length}/${results.length} cases passed`);

  if (failed.length > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
