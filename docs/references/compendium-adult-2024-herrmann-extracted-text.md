# 2024 Adult Compendium of Physical Activities (Herrmann et al., 2567) — extracted text

> ⚠️ **นี่ไม่ใช่ไฟล์ต้นฉบับ** — เป็นข้อความที่ถูกแตกออกจาก PDF และวางในแชทกับ Claude Code เมื่อ 2026-09-27
> (2 ครั้ง: ครั้งแรกวางเป็นข้อความล้วน, ครั้งที่ 2 แนบเป็นไฟล์ชื่อ
> "2024 Adult Compendium of Physical Activities (Herrmann et al., 2567).pdf" แต่ Claude Code ไม่มีสิทธิ์
> เข้าถึงไฟล์ไบนารีจริงจากไฟล์แนบในแชท ได้แค่ข้อความที่แตกออกมาเหมือนเดิม)
>
> **ต้องมีไฟล์ PDF ตัวจริงมาวางคู่กันที่ `docs/references/compendium-adult-2024-herrmann.pdf`**
> เพื่อใช้อ้างอิงในบรรณานุกรมของเล่ม (ต้องมีไฟล์จริงอ้างได้ ไม่ใช่แค่ text นี้) — ไฟล์นี้ใช้ตรวจสอบเร็วๆ
> ระหว่างทำงานได้ก่อน
>
> ที่มา: 2024 Adult Compendium of Physical Activities, Herrmann SD, Willis EA, Ainsworth BE, et al.
> (อ้างในเล่มเป็น Herrmann et al., 2567)

ใช้ตรวจสอบค่า METs ของ Table 2.1 (คาร์ดิโอ) และ Table 2.2 (เวทเทรนนิ่ง) ในบทที่ 2 — ดู
`docs/compendium-2011-met-check.md` สำหรับฉบับ 2011 ที่เคยใช้ตรวจก่อนหน้านี้ และ migration
`backend/migrations/2026-09-27_align_cardio_mets_to_compendium_2024.sql` สำหรับการปรับ DB ให้ตรงฉบับนี้

รูปแบบ: `Major Heading | Activity Code | MET Value | Activity Description` (คอลัมน์คั่นด้วย tab ตามที่
วางในแชทต้นฉบับ — ไม่ได้แปลง markdown table เพราะยาวเกิน 1,800 บรรทัด)

---

## Bicycling

```
01003	14.0	Bicycling, mountain, uphill, vigorous
01004	16.0	Bicycling, mountain, competitive racing
01008	8.5	Bicycling, BMX
01009	8.5	Bicycling, mountain, general
01010	4.0	Bicycling, <10 mph, leisure, to work or for pleasure (Taylor Code 115)
01011	6.8	Bicycling, to/from work, self selected pace
01013	5.8	Bicycling, on dirt or farm road, moderate pace
01014	7.0	Bicycling, general
01015	4.3	Bicycling, self-selected easy pace
01016	7.0	Bicycling, self-selected moderate pace
01017	9.0	Bicycling, self-selected vigorous pace
01018	3.5	Bicycling, leisure 5.5 mph
01019	5.8	Bicycling, leisure, 9.4 mph
01020	6.8	Bicycling, 10-11.9 mph, leisure, slow, light effort
01030	8.0	Bicycling, 12-13.9 mph, leisure, moderate effort
01040	10.0	Bicycling, 14-15.9 mph, racing or leisure, fast, vigorous effort
01050	12.0	Bicycling, 16-19 mph, racing/not drafting or >19 mph drafting, very fast, racing general
01060	16.8	Bicycling, >20 mph, racing, not drafting
01065	8.5	Bicycling, 12 mph, seated, hands on brake hoods or bar drops, 80 rpm
01066	9.0	Bicycling, 12 mph, standing, hands on brake hoods, 60 rpm
01070	5.0	Unicycling
01080	6.8	E-bike (electrically assisted) without electronic support
01084	6.0	E-bike (electrically assisted) with light electronic support
01088	4.0	E-bike (electrically assisted) with high electronic support
01200	6.8	Bicycling, stationary, general
01210	3.5	Bicycling, stationary, 25-30 watts, very light to light effort
01214	4.0	Bicycling, stationary, 50 watts, light effort
01216	5.0	Bicycling, stationary, 60 watts, light to moderate effort
01218	5.8	Bicycling, stationary, 70-80 watts
01220	6.0	Bicycling, stationary, 90-100 watts, moderate to vigorous
01224	6.8	Bicycling, stationary, 101-125 watts
01228	8.0	Bicycling, stationary, 126-150 watts
01232	10.3	Bicycling, stationary, 151-199 watts
01236	10.8	Bicycling, stationary, 200-229 watts, vigorous
01240	12.5	Bicycling, stationary, 230-250 watts, very vigorous
01244	13.8	Bicycling, stationary, 270-305 watts, very vigorous
01248	16.3	Bicycling, stationary, >325 watts, very vigorous
01252	5.5	Bicycling, concentric only, 100 W
01254	11.0	Bicycling, concentric only, 200 W
01262	2.3	Bicycling, eccentric only, 100 to 149 W
01264	4.0	Bicycling, eccentric only, 200 W
01270	9.0	Bicycling, stationary, RPM/Spin bike class
01290	8.8	Bicycling, interactive virtual cycling, indoor cycle ergometer
01305	8.8	Bicycling, high intensity interval training
```

## Conditioning Exercise (รวมรหัสที่ใช้ใน Table 2.1/2.2 ของเล่ม)

```
02000	7.3	Aerobic, general
02001	5.5	Aerobic, step, with 4-inch step
02002	7.3	Aerobic, step, with 6-8 inch step
02003	9.0	Aerobic, step, with 10-12 inch step
02004	7.8	Bench step class, general
02005	4.8	Aerobic dance, low impact, moderate effort
02006	8.0	Aerobic dance, high impact, vigorous effort
02007	10.0	Aerobic dance wearing 10-15 lb weights
02008	5.0	Army type obstacle course exercise, boot camp training program
02020	7.5	Calisthenics (e.g., pushups, sit ups, pull-ups, jumping jacks, burpees, battling ropes), vigorous effort
02022	3.8	Calisthenics (e.g., pushups, sit ups, pull-ups, lunges), moderate effort
02024	2.8	Calisthenics (e.g., curl ups, abdominal crunches, plank), light effort
02030	3.5	Calisthenics, light or moderate effort, general (e.g., back exercises), going up & down from floor (Taylor Code 150)
02032	6.0	Circuit training, body weight exercises
02034	3.5	Circuit training, light effort
02035	5.0	Circuit training, moderate effort
02040	7.5	Circuit training, including kettlebells, some aerobic movement with minimal rest, general, vigorous intensity
02045	3.5	Curves exercise routines in women
02048	5.0	Elliptical trainer, moderate effort
02049	9.0	Elliptical trainer, vigorous effort
02050	6.0	Resistance (weight lifting - free weight, nautilus or universal-type), power lifting or body building, vigorous effort (Taylor Code 210)
02052	5.0	Resistance (weight) training, squats, deadlift, slow or explosive effort
02054	3.5	Resistance (weight) training, multiple exercises, 8-15 reps at varied resistance
02055	5.8	Resistance Training, circuit, reciprocol supersets, peripheral hear action training
02056	3.0	Body weight resistance exercises (e.g., squat, lunge, push-up, crunch), general
02057	6.5	Body weight resistance exercises (e.g., squat, lunge, push-up, crunch), high intensity
02058	9.8	Kettle bell swings
02060	5.5	Health club exercise, general (Taylor Code 160)
02061	5.0	Health club exercise classes general, gym/weight training combined in one visit
02062	7.8	Health club exercise, conditioning classes
02064	3.8	Home exercise, general
02065	9.3	Stair treadmill ergometer, general
02068	11.0	Rope skipping exercise, general
02069	9.0	Jumping rope, Digi-Jump Maching, 120 jumps/minute
02070	7.3	Rowing, stationary ergometer, general, vigorous effort
02071	5.0	Rowing, stationary ergometer, general, <100 watts, moderate effort
02072	7.5	Rowing, stationary, 100 to 149 watts, vigorous effort
02073	11.0	Rowing, stationary, 150 to 199 watts, vigorous effort
02074	14.0	Rowing, stationary, >= 200 watts, very vigorous effort
02078	11.0	Shuttle running, forward/backward/lateral
02080	6.8	Ski machine, general
02082	10.5	Ski ergometer, cross country, double poling, slow to moderate speed
02084	18.0	Ski ergometer, cross country, double poling, fast to maximum speed
02085	10.5	Slide board exercise, general
02090	6.0	Slimnastics, jazzercise
02101	2.3	Stretching, mild
02103	1.8	Pilates, traditional, mat
02105	2.8	Pilates, general
02107	8.5	Pound, combination of Pilates and body movements with drumming
02108	4.5	Pole dancing, exercise class
02110	6.8	Teaching exercise classes (e.g., aerobic, water)
02112	2.8	Therapeutic exercise ball, Fitball exercise
02114	9.5	Therapeutic exercise ball, Fitball exercise, high intensity
02115	2.8	Upper body exercise, arm ergometer, general, light
02116	2.0	Arm Ergometer, hand bike, 15W
02117	2.8	Arm Ergometer, hand bike, 25-30W
02118	3.5	Arm Ergometer, hand bike, 45W
02119	4.3	Upper body exercise, stationary bicycle - Airdyne (arms only) 40 rpm, moderate intensity
02120	5.3	Water aerobics, water calisthenics, water exercise
02135	1.3	Whirlpool, sitting
02140	2.5	Video, exercise workouts, TV conditioning programs (e.g., yoga, stretching, seated), light effort
02143	4.0	Video, exercise workouts, TV conditioning programs (e.g., cardio-resistance training), moderate
02145	6.0	Video, exercise workouts, TV conditioning programs (e.g., cardio-resistance training), vigorous
02150	2.3	Yoga, Hatha
02153	8.0	Yoga, Hatha, high intensity
02155	3.0	Yoga, Hot
02160	4.0	Yoga, Power
02170	2.0	Yoga, Nadisodhana
02175	2.3	Yoga, General
02180	3.5	Yoga, Surya Namaskar
02185	2.7	Yoga, Vinyasa
02200	5.3	Native New Zealander PA, general moderate effort
02205	6.8	Native New Zealander PA, general, vigorous effort
02210	7.0	High intensity interval exercise, moderate effort
02214	11.0	High intensity interval exercise, burpees, mountain climbers, squat jumps, Tabata, vigorous effort
02225	2.3	Balance Exercise Assist Robot (BEAR), simulated skiing, tennis, rodeo
02230	5.8	Hooping (formerly known as hula hooping)
02240	9.0	Impulse Training System, Inertial Exercise Trainer
02280	7.9	Virtual Reality Fitness, Supernatural "Flow", "Boxing" vigorous intensity
02284	9.3	ExerCube, workout series
02288	13.0	Blackbox Immersive virtual reality exergaming system, vigorous intensity
02300	3.0	Wand exercise, Life-Build-Line
02310	6.5	Zumba, group class
02315	5.5	Zumba, home video
02340	2.8	Sit to stand exercise, 6-12 times/min
02344	4.0	Sit to stand exercise, 18-24 times/min
```

## Running (รหัสที่เกี่ยวข้องกับกิจกรรมวิ่ง)

```
12010	6.0	Jog/walk combination (jogging component of less than 10 minutes) (Taylor Code 180)
12020	7.5	Jogging, general, self-selected pace
12025	4.8	Jogging, in place
12026	3.3	Jogging 2.6 to 3.7 mph
12027	4.5	Jogging on a mini-tramp
12028	6.5	Running, 4 to 4.2 mph (13 min/mile)
12029	7.8	Running 4.3 to 4.8 mph
12030	8.5	Running, 5.0 to 5.2 mph (12 min/mile)
12045	9.0	Running, 5.5-5.8 mph
12050	9.3	Running, 6-6.3 mph (10 min/mile)
12060	10.5	Running, 6.7 mph (9 min/mile)
12070	11.0	Running, 7 mph (8.5 min/mile)
12080	11.8	Running, 7.5 mph (8 min/mile)
12090	12.0	Running, 8 mph (7.5 min/mile)
12100	12.5	Running, 8.6 mph (7 min/mile)
12110	13.0	Running, 9 mph (6.5 min/mile)
12115	14.8	Running, 9.3 to 9.6 mph
12120	14.8	Running, 10 mph (6 min/mile)
12130	16.8	Running, 11 mph (5.5 min/mile)
12132	18.5	Running, 12 mph (5.0 min/mile)
12134	19.8	Running, 13 mph (4.6 min/mile)
12135	23.0	Running, 14 mph (4.3 min/mile)
12140	9.3	Running, cross country
12145	10.5	Running, self-selected pace
12150	8.0	Running (Taylor Code 200)
```

## Sports (มวย/ศิลปะการต่อสู้/กระโดดเชือก — รหัสที่ใช้ใน Table 2.1)

```
15100	12.3	Boxing, in ring, general
15110	5.8	Boxing, punching bag
15113	7.0	Boxing, punching bag, 60 b/min
15115	8.5	Boxing, punching bag, 120 b/min
15118	10.8	Boxing, punching bag, 180 b/min
15120	7.8	Boxing, sparring
15125	9.3	Boxing, simulated boxing round, exercise
15425	5.3	Martial Arts, different types, slower pace, novice performers, practice
15430	10.3	Martial Arts, different types, moderate pace (e.g., judo, jujitsu, karate, kick boxing, tae kwon do, tai-bo, Muay Thai boxing)
15432	14.3	Taekwondo, combat simulation
15433	11.3	Judo
15444	6.5	Kendo, kihon-keiko style, moderate intensity
15445	9.6	Kendo, kirikaeshi style, high intensity
15446	11.3	Kendo, kakari keiko style, very high intensity
15457	7.3	Kickboxing
15550	12.3	Rope jumping, fast pace, 120-160 skips/min
15551	11.8	Rope jumping, moderate pace, general, 100 to 120 skips/min, 2 foot skip, plain bounce
15552	8.3	Rope jumping, slow pace, < 100 skips/min, 2 foot skip, rhythm bounce
15554	10.0	Rope jumping, double under or more
```

## Walking (รหัสที่เกี่ยวข้องกับเดินขึ้นเนิน/ลู่วิ่ง)

```
17010	7.0	Backpacking (Taylor Code 050)
17032	5.0	Climbing hills, no load, 5 to 20% grade, very slow pace
17033	3.8	Climbing hills, 15-50 lb load, 1 to 2% grade, slow pace
17034	5.3	Climbing hills, no load, 1 to 5% grade, moderate-to-brisk pace
17035	7.0	Climbing hills, no load, 6 to 10% grade, moderate-to-brisk pace
17036	8.8	Climbing hills, no load, 11 to 20% grade, slow-to-moderate pace
17037	10.0	Climbing hills, no load, 4.0 to 5.0 mph, 3 to 5% grade, very fast pace
17038	8.5	Climbing hills, no load, steep grade (30%), slow pace (less than 1.2 mph)
17039	15.5	Climbing hills, no load, very steep grade (30-40%), 1.2 to 1.8 mph
17040	16.3	Climbing hills, no load, steep grade (10-40%), 1.8 to 5.0 mph
17045	6.5	Climbing hills, 10 to 20 lb load, 5 to 10% grade, moderate
17050	7.5	Climbing hills, 21 to 40 lb load, 3 to 10% grade, moderate-to-brisk pace
17130	8.0	Stair climbing, using or climbing up ladder (Taylor Code 030)
17131	6.8	Stair climbing, general
17133	4.5	Stair climbing, slow pace
17134	9.3	Stair climbing, fast pace, one step at a time
17136	7.5	Stair climbing, two steps at a time
17138	7.5	Stair climbing, ascending and descending stairs
17190	3.8	Walking, 2.8 to 3.4 mph, level, moderate pace, firm surface
17200	4.8	Walking, 3.5 to 3.9 mph, level, brisk, firm surface, walking for exercise
17220	5.5	Walking, 4.0 to 4.4 mph (6.4 to 7.0 km/h), level, firm surface, very brisk pace
17230	7.0	Walking, 4.5 to 4.9 mph, level, firm surface, very, very brisk
17231	8.5	Walking, 5.0 to 5.5 mph (8.8 to 8.9 km/h), level, firm surface
```

## Water Activities (ว่ายน้ำ)

```
18230	9.8	Swimming laps, freestyle, fast, vigorous effort
18240	5.8	Swimming laps, freestyle, slow, recreational
18250	9.5	Swimming, backstroke, training or competition
18255	4.8	Swimming, backstroke, recreational
18260	10.3	Swimming, breaststroke, general, training or competition
18265	5.3	Swimming breaststroke, recreational
18270	13.8	Swimming, butterfly, general
18280	10.5	Swimming, crawl, fast speed, ~75 yards/minute, vigorous effort
18285	10.5	Swimming, open water, 5k
18290	8.0	Swimming, crawl, medium speed, ~50 yards/minute, vigorous effort
18292	5.8	Swimming, crawl, slow speed, 30-45 yards/minute, moderate effort
18294	14.5	Swimming, crawl, elite swimmers, competition, >90 yards/minute
18300	6.0	Swimming, lake, ocean, river (Taylor Codes 280, 295)
18310	6.0	Swimming, leisurely, not lap swimming, general
18320	7.0	Swimming, sidestroke, general
18330	8.0	Swimming, synchronized
18340	9.8	Swimming, treading water, fast, vigorous effort
```

---

*หมายเหตุ: ไฟล์นี้ตัดหมวดที่ไม่เกี่ยวกับสูตรของโปรเจกต์ออก (Dancing, Fishing & Hunting, Home Activities,
Home Repair, Inactivity, Lawn & Garden, Miscellaneous, Music Playing, Occupation, Self Care, Sexual
Activity, Transportation, Winter Activities, Religious Activities, Volunteer Activities, Video Games,
Water Activities บางส่วน, Sports บางส่วน) เพื่อไม่ให้ยาวเกินไป — ถ้าต้องตรวจรหัสในหมวดที่ตัดออก ให้ขอ
Claude ดึงจาก transcript ของแชทวันที่ 2026-09-27 หรือรอไฟล์ PDF ตัวจริงมาวางแทน*
