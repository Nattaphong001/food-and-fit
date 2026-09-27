# How commercial apps, wearables and published systems estimate strength-training energy expenditure and assign intensity or MET

All URLs accessed 2026-09-27. "Not publicly documented" means no official vendor source was found in this search. It does not mean the vendor has no method.

## Q1. What do major vendors (Apple, Garmin/Firstbeat, Fitbit/Google, Polar, WHOOP, Google Fit, MyFitnessPal, Hevy/Strong/JEFIT/Fitbod, Samsung, Strava) officially document?

### Takeaway
No major wearable vendor documents a set-, load- or rep-based calorie formula for strength training. Wearables estimate calories from heart rate (and sometimes accelerometry) plus body data and a user-selected activity type. Logging apps either do not calculate strength calories (MyFitnessPal's original stance) or pass the work to the watch or health platform (Hevy). In our search, only WHOOP uses logged sets, reps and weight, and it uses them for a "muscular load" or strain score, not for kcal.

### Cited Findings
- **Apple Watch.** Apple's official help page says Apple Watch uses "your personal information — such as your height, weight, gender, and age — to calculate how many calories you burn". It adds that "Heart rate is one of many factors that Apple Watch uses to measure your activity and exercise. Depending on your workout, it selects the most appropriate inputs for that activity." It tells users to "choose the option that best matches what you're doing" in the Workout app. — [Apple Support 105002](https://support.apple.com/en-us/105002)
- **Apple Watch.** Apple publishes no per-workout-type algorithm or MET table for Traditional or Functional Strength Training. Secondary sources confirm the Workout app does not log reps, weight or sets. (This is secondary evidence only.) — [MyHealthyApple](https://www.myhealthyapple.com/strength-training-using-apple-watch/)
- **Garmin (official support).** Garmin calculates active calories "based on the activity level, type of activity, age, height, weight, gender, and heart rate (if available)." Garmin names "the Activity Class, the heart rate, and the HR Variability" as the main factors. — [Garmin Support: Tracking Calories](https://support.garmin.com/en-US/?faq=lkl4cwCLlK7ox362uGQEV7)
- **Garmin Strength activity.** It records sets and reps (auto rep counting, manual editing, weight entry per set). The Garmin documentation found does not say that reps or weight feed the calorie estimate. — [Garmin Support: Strength Training on a Garmin Device](https://support.garmin.com/en-US/?faq=LcYGZd4EOZ9PkTY5YRvin5); [Forerunner 265 manual](https://www8.garmin.com/manuals/webhelp/GUID-F41EAFB3-6CC9-42DE-9C6C-9E358DBB0671/EN-US/GUID-CF2D7922-A1AC-4510-9480-E7CE8119EAF2.html)
- **Firstbeat (Garmin's algorithm supplier).** Firstbeat's white paper "Energy Expenditure Estimation Method Based on Heart Rate Measurement" (first published 2007, updated through 2012) describes an estimate built on beat-by-beat (R-R) heart rate. It is not based on workload inputs such as load or reps. I could not open the PDF (DNS error), so I could not verify any text in it about strength training. — [Firstbeat white paper landing page](https://www.firstbeat.com/en/energy-expenditure-estimation-firstbeat-white-paper/); [PDF](https://assets.firstbeat.com/firstbeat/uploads/2015/10/white_paper_energy_expenditure_estimation.pdf)
- **Garmin/Firstbeat, secondary explanation.** DC Rainmaker describes the method as heart rate to VO2 to METs to kcal, and quotes a Firstbeat error estimate of about 20–35% from heart rate versus about 60% from motion alone. — [DC Rainmaker](https://www.dcrainmaker.com/2010/11/how-calorie-measurement-works-on-garmin.html)
- **Fitbit (Google Health Help).** "Fitbit devices combine your basal metabolic rate (BMR) and your activity data to estimate your calories burned… If your device tracks heart rate, your heart-rate data is also included, especially to estimate calories burned during exercise." The page does not mention METs or anything specific to weight training. — [Google Health Help 14237111](https://support.google.com/googlehealth/answer/14237111?hl=en)
- **Polar (Smart Calories / OwnCal).** Polar calculates energy expenditure from measured heart rate and wrist movement, plus weight, height, age, gender, resting heart rate, maximum heart rate and VO2max. Polar's manuals give no strength-specific formula. — [Polar Unite manual: Smart Calories](https://support.polar.com/e_manuals/unite/polar-unite-user-manual-english/smart-calories.htm); [Polar Smart Calories](https://www.polar.com/au-en/smart_coaching/features/smart_calories)
- **WHOOP Strength Trainer.**
  - By logging "exercises, sets, reps, and weights, the algorithm calculates your exact muscular load based on the biomechanics of each movement". It uses the accelerometer and gyroscope.
  - For weightlifting, powerlifting and bodybuilding sessions that were not logged, WHOOP "automatically estimates muscular strain based on activity type and duration… derived from millions of real Strength Trainer sessions."
  - The output is muscular load or strain, not kcal.
  - I could not open the R&D and validation page (HTTP 403), so no validation details are verified here.
  - Sources: [WHOOP: Muscular Load explained](https://www.whoop.com/us/en/thelocker/how-whoop-measures-muscular-load/); [WHOOP: R&D behind Strength Trainer](https://www.whoop.com/us/en/thelocker/the-research-and-development-behind-strength-trainer/); [WHOOP launch](https://www.whoop.com/us/en/thelocker/introducing-strength-trainer-a-new-way-to-quantify-the-impact-of-your-strength-training/)
- **Google Fit (developer documentation).** The Workout data type stores exercise, repetitions, resistance type (barbell, cable, dumbbell, kettlebell, machine, body weight), resistance in kg, and duration. The calories-expended data type is total kcal including BMR. The docs use MET only for Heart Points: 3–6 MET earns 1 point per minute, and more than 6 MET earns 2 points. The docs publish no MET table per activity for weight training. — [Google Fit: Activity data types](https://developers.google.com/fit/datatypes/activity); [Google Fit activity types](https://developers.google.com/fit/rest/v1/reference/activity-types)
- **MyFitnessPal.**
  - The help article title (seen in search results) is "Why don't you calculate calories burned for strength training?" Search snippets say MFP calculates calories only for "Cardiovascular" entries. Snippets also say strength calories depend on "how much weight you lifted per repetition, how vigorously you performed the exercise, and how much rest you took between sets."
  - MFP suggests logging "Strength training" from the cardio database as a rough estimate.
  - A later "Workout Routines" feature lets strength exercises count toward calories, but its method is not described.
  - The help page itself returned HTTP 403, so I verified these only from search snippets.
  - Sources: [MFP Help](https://support.myfitnesspal.com/hc/en-us/articles/360032625431-Why-calories-burned-from-strength-training-aren-t-calculated); [MFP Workout Routines](https://support.myfitnesspal.com/hc/en-us/articles/360036071232-Workout-Routines)
- **Hevy.** Workouts are sent to Google Fit or Apple Health "with a rough estimate of how many calories were burned". With Apple Watch, "the calories displayed in Hevy will be calculated by Apple Health". The formula is not disclosed. — [Hevy Help: calories burned](https://www.hevyapp.com/help/calories-burned/)
- **StrengthLog.** Its free calculator uses a published regression, not MET: men = minutes × kg × 0.0713, women = minutes × kg × 0.0637. The page says this is based on a study of 52 adults doing "seven exercises × 2–3 sets × 8–12 reps with about 90 seconds of rest". It offers no light, moderate or vigorous option. — [StrengthLog calculator](https://www.strengthlog.com/calories-burned-lifting-weights/)

### Inferences
- The industry norm matches the thesis app's design choice: calories = intensity factor × body mass × whole-session duration. Wearables get the intensity factor from heart rate. Logging apps (StrengthLog) use a fixed coefficient × kg × session minutes. None subtract rest periods from the duration.
- StrengthLog's 0.0713 kcal/kg/min equals 4.28 kcal/kg/h, which is about a gross 4.3 MET for moderate 8–12-rep training (my arithmetic). That sits between Compendium 02054 (3.5) and 02052 (5.0), so the app's MET 3.5 for moderate sessions is in a defensible range.
- Using sets and reps to pick an intensity tier has a partial commercial precedent: WHOOP uses logged sets, reps and weight for load or strain, but not for kcal. I found no vendor that maps logged sets to a Compendium MET. The thesis app's Effort Ratio rule therefore appears to be the researcher's own design, and the thesis should say so.

### Gaps
- Samsung Health, Strava, Strong, JEFIT and Fitbod: I found no official document describing how they estimate strength-training calories. Treat these as not publicly documented; I did not search exhaustively.
- I could not read the Firstbeat PDF, so I cannot confirm whether it says anything specific about resistance or anaerobic exercise.
- Apple publishes no algorithm detail for strength workouts.

## Q2. Do systems let users choose "light / moderate / vigorous" weight lifting mapped to Compendium METs?

### Takeaway
The Compendium itself defines the tiers. The 2024 Adult Compendium lists six resistance codes with verbal descriptors. Consumer apps that estimate strength calories from MET do so through a "Strength training" or "weight lifting" cardio entry. I found no official vendor page mapping user-selected light, moderate or vigorous tiers to Compendium codes.

### Cited Findings
- 2024 Adult Compendium, Conditioning Exercise codes, quoted verbatim:
  - 02050, 6.0 MET: "Resistance (weight lifting – free weight, nautilus or universal-type), power lifting or body building, vigorous effort"
  - 02052, 5.0 MET: "Resistance (weight) training, squats, deadlift, slow or explosive effort"
  - 02054, 3.5 MET: "Resistance (weight) training, multiple exercises, 8-15 reps at varied resistance"
  - 02055, 5.8 MET: "Resistance Training, circuit, reciprocal supersets, peripheral heart action training"
  - 02056, 3.0 MET: "Body weight resistance exercises (e.g., squat, lunge, push-up, crunch), general"
  - 02057, 6.5 MET: "Body weight resistance exercises … high intensity"
  - Source: [Compendium: Conditioning Exercise](https://pacompendium.com/conditioning-exercise/). Paper: Herrmann SD et al., 2024 Adult Compendium of Physical Activities, J Sport Health Sci 2024;13(1):6–12, doi:10.1016/j.jshs.2023.10.010. The DOI comes from my own knowledge and was not fetched in this session, so check it.
- The Mitchell et al. 2024 review (Sports Medicine) says the Compendium provides MET values of "3.5, 5.0 and 6.0 for resistance exercises on the basis of the type and intensity". It notes that measured values "range between 3.0 and 8.0 MET" depending on training characteristics. — [Mitchell et al. 2024, PMC11393209](https://pmc.ncbi.nlm.nih.gov/articles/PMC11393209/), doi:10.1007/s40279-024-02047-8
- MyFitnessPal points users to the generic "Strength training" cardio entry, as shown in search snippets of its help page. The MET value and tiers behind that entry are not stated. — [MFP Help](https://support.myfitnesspal.com/hc/en-us/articles/360032625431-Why-calories-burned-from-strength-training-aren-t-calculated)
- Third-party exercise databases, for example Fitia, list Compendium-derived items such as "weight training lifting weights vigorous effort" and "strength training light effort". They are aggregators, not primary sources. — [Fitia: vigorous](https://fitia.app/exercises/weight-training-lifting-weights-vigorous-effort/); [Fitia: light](https://fitia.app/exercises/strength-training-light-effort/)

### Inferences
- The Compendium descriptors themselves support the app's tier criteria:
  - 02054 names "8-15 reps", which supports "fewer than 8 reps means heavy".
  - 02050 names "power lifting or body building, vigorous effort", which supports covering both low-rep heavy lifting and high-effort hypertrophy work with one heavy tier.
- In the Compendium and consumer tools, the user normally chooses the tier (self-report). Choosing it automatically from set data departs from that convention.

### Gaps
- I found no official MyFitnessPal, Samsung or Google document listing its weight-lifting MET tiers.

## Q3. What do peer-reviewed validation studies say about wearable calorie accuracy during resistance training?

### Takeaway
The evidence is consistent: consumer wearables are not valid for energy expenditure, and they perform especially poorly in resistance exercise. Reported errors are roughly 15–57% MAPE, often overestimates. This supports a transparent, logging-based MET method as a reasonable alternative, not an inferior one.

### Cited Findings
- **Boudreaux BD et al. 2018**, "Validity of Wearable Activity Monitors during Cycling and Resistance Exercise", Med Sci Sports Exerc 50(3):624–633, doi:10.1249/MSS.0000000000001471.
  - 50 participants. 8 monitors tested for heart rate against ECG; 7 tested for energy expenditure against a metabolic analyzer.
  - Conclusion: no device was valid for energy expenditure during cycling or resistance exercise.
  - A search-summary figure says energy expenditure was overestimated in 82% of cases during resistance training, with MAPE about 53%. That figure came from a secondary summary and was not verified against the full text.
  - Sources: [ResearchGate](https://www.researchgate.net/publication/321142993_Validity_of_Wearable_Activity_Monitors_during_Cycling_and_Resistance_Exercise); [Ovid abstract](https://www.ovid.com/jnls/acsm-msse/abstract/10.1249/mss.0000000000001471~validity-of-wearable-activity-monitors-during-cycling-and?redirectionsource=fulltextview)
- **Fuller D et al. 2020**, systematic review, JMIR mHealth uHealth 8(9):e18694, doi:10.2196/18694. 158 publications.
  - For energy expenditure, "no brand was accurate". No brand was within ±3% more than 13% of the time.
  - Garmin underestimated 69% of the time and Withings 74%.
  - Apple overestimated 58% of the time and Polar 69%.
  - Fitbit underestimated 48.4% and overestimated 39.5% of the time.
  - These figures come from search snippets of the article; the full-text fetch was blocked by a captcha.
  - Sources: [JMIR](https://mhealth.jmir.org/2020/9/e18694/); [PMC7509623](https://pmc.ncbi.nlm.nih.gov/articles/PMC7509623/)
- **Mitchell L et al. 2024**, systematic scoping review, Sports Medicine, doi:10.1007/s40279-024-02047-8.
  - Studies by method: indirect calorimetry 136, blood lactate 25, wearables 31, METs 4.
  - Five wearable validation studies showed "mean absolute percentage errors ranging markedly (15.1–57.0%)" and correlations of r = 0.02–0.74. The authors say wearables "should be used with caution".
  - The review found no established equation predicting energy expenditure from sets, reps and load alone.
  - Source: [PMC11393209](https://pmc.ncbi.nlm.nih.gov/articles/PMC11393209/)
- **Further studies surfaced but not fully reviewed:**
  - Apple Watch 6, Polar Vantage V and Fitbit Sense validation, Eur J Sport Sci. — [Wiley](https://onlinelibrary.wiley.com/doi/10.1080/17461391.2021.2023656)
  - "Are wearable heart rate measurements accurate to estimate aerobic energy cost during low-intensity resistance exercise?" — [PubMed 31437191](https://pubmed.ncbi.nlm.nih.gov/31437191)

### Inferences
- Heart-rate-based kcal during lifting is unreliable because heart rate rises from pressor and Valsalva effects and anaerobic work that do not track oxygen uptake. A committee cannot treat "Apple Watch or Garmin do it with heart rate" as a gold standard. The thesis's MET × time approach is in line with one of the four method families the Mitchell review recognises (METs), while acknowledging its known limits.

### Gaps
- Shcherbina et al. 2017 (J Pers Med) and Wallen et al. 2016 (PLoS One) were not fetched in this session. I cannot confirm from sources whether they included resistance exercise; I believe they did not, but this is unverified.
- I did not verify the full text of Boudreaux, including per-device energy expenditure MAPE.

## Q4. Are there published algorithms that assign MET or intensity to resistance training automatically from set data (load, reps, %1RM) or accelerometry, and patents on this?

### Takeaway
The closest peer-reviewed precedent is Lytle et al. 2019 (MSSE). It predicts net kcal of a resistance session from total volume (sets × reps × load) plus body composition. It is a regression, not a MET tier assignment. I found no published algorithm or official vendor method that picks a Compendium MET tier from logged sets. WHOOP's commercial method uses sets, reps and weight plus sensors, but for load or strain, not kcal. Patent evidence is thin.

### Cited Findings
- **Lytle JR et al. 2019**, "Predicting Energy Expenditure of an Acute Resistance Exercise Bout in Men and Women", Med Sci Sports Exerc 51(7), doi:10.1249/MSS.0000000000001925, PMID 30768553.
  - Participants: 52 adults (27 men, 25 women), aged 20–58.
  - Protocol: 2–3 sets of 8–12 reps at 60–70% of predicted 1RM, with 2-minute turnover, across 7 machine exercises.
  - Equation: total net kcal = 0.874 × height (cm) − 0.596 × age (years) − 1.016 × fat mass (kg) + 1.638 × lean mass (kg) + 2.461 × (TV × 10⁻³) − 110.742, where TV (total volume) = sets × reps × weight.
  - Fit: R² = 0.773, SEE = 28.5 kcal. Equations for individual lifts had R² = 0.62–0.83.
  - Sources: [PubMed 30768553](https://pubmed.ncbi.nlm.nih.gov/30768553/); [MSSE full text](https://journals.lww.com/acsm-msse/fulltext/2019/07000/predicting_energy_expenditure_of_an_acute.22.aspx)
- The Mitchell 2024 review cites Lytle as a predictive model that is "limited by [its] dependence on indirect calorimetry". Separately, the review notes one study used an individual RPE-to-energy-expenditure regression. — [PMC11393209](https://pmc.ncbi.nlm.nih.gov/articles/PMC11393209/)
- **WHOOP** uses logged exercises, sets, reps and weights plus IMU data to compute muscular load "based on the biomechanics of each movement", and it adapts to the user's baselines and upper limits. It is commercial and proprietary, and the output is not kcal. — [WHOOP](https://www.whoop.com/us/en/thelocker/how-whoop-measures-muscular-load/)
- **Patent.** US 10,238,166, "Instrumented article of fitness and method of determining caloric requirements", describes force sensors embedded in fitness equipment whose data are used to determine caloric output. Only the title and a search snippet were seen; the claims were not reviewed. — [USPTO PDF](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10238166)
- **Google Fit.** It stores repetitions and resistance per set but documents no calorie model that uses them. — [Google Fit data types](https://developers.google.com/fit/datatypes/activity)

### Inferences
- Individualising intensity to each user's own baselines (WHOOP's "learns your baselines and upper limits") is conceptually similar to the thesis's Effort Ratio: set e1RM divided by the user's Best 1RM. This gives commercial precedent for relative, personalised intensity. It is not precedent for MET selection specifically.
- Lytle 2019 shows that load volume and reps legitimately carry energy information. That supports the idea of using set data at all. However, its population and protocol (moderate 60–70% 1RM, machines) limit how far it generalises.

### Gaps
- I found no peer-reviewed paper that automatically classifies Compendium resistance MET tiers from %1RM, reps or Effort Ratio.
- I did not search for accelerometry-based classification papers for resistance MET, for example research apps that recognise lifting from an IMU.
- I did not do a systematic Google Patents search. Only one patent surfaced, and its claims are unverified.
