/**
 * Causal Graph Editor Module
 * Cytoscape.js + ELK layout for evidence-based bruxism causal network
 */

import * as storage from './storage.js';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

const STYLE_CLASS_COLORS = {
    robust:       '#1b4332',
    moderate:     '#b45309',
    preliminary:  '#6b21a8',
    symptom:      '#1e3a5f',
    mechanism:    '#374151',
    intervention: '#065f46',
};
const FEEDBACK_COLOR = '#ef4444';

// ═══════════════════════════════════════════════════════════
// DEFAULT GRAPH DATA — Evidence-based bruxism causal network
//
// COLOUR KEY (styleClass):
//   robust    (dark green) = RCT / meta-analytic / replicated
//   moderate  (orange)     = well-designed observational
//   preliminary (purple)   = small N, single study, or theoretical
//   symptom   (blue)       = downstream symptoms
//   mechanism (grey)       = mechanistic intermediaries
//   intervention (teal)    = treatment / intervention points
//
// CITATIONS: see tooltip objects and edge labels
// ═══════════════════════════════════════════════════════════

const DEFAULT_GRAPH_DATA = {
    nodes: [
        // ── CONFIRMED INPUTS ──
        { data: { id: 'STRESS', label: 'Stress & Anxiety\nOR 2.07', styleClass: 'moderate', confirmed: 'yes',
            tooltip: { evidence: 'Moderate (observational)', stat: 'OR 2.07 (95% CI 1.26-3.40)', citation: 'Chemelo 2020, J Oral Rehabil', mechanism: 'HPA axis activation drives cortisol and sympathetic shift' } } },
        { data: { id: 'HEALTH_ANXIETY', label: 'Health Anxiety', styleClass: 'moderate', confirmed: 'yes',
            tooltip: { evidence: 'Moderate', stat: 'User-confirmed input', citation: 'Clinical self-report', mechanism: 'Health anxiety amplifies stress response and hypervigilance' } } },

        // ── REFLUX PATHWAY ──
        { data: { id: 'OSA', label: 'Sleep Apnea / UARS', styleClass: 'moderate', confirmed: 'no',
            tooltip: { evidence: 'Moderate', stat: '62-78% comorbid with GERD', citation: 'Multiple systematic reviews', mechanism: 'Airway obstruction triggers microarousals and negative pressure reflux' } } },
        { data: { id: 'GERD', label: 'GERD / Silent Reflux\nOR 6.87', styleClass: 'robust', confirmed: 'yes',
            tooltip: { evidence: 'Robust (RCT + meta)', stat: 'OR 6.87 (Li 2018)', citation: 'Li 2018; Ohmure 2011 RCT', mechanism: 'Acid micro-aspiration triggers vagal afferents and protective RMMA' } } },

        // ── AROUSAL & BRUXISM ──
        { data: { id: 'SLEEP_DEP', label: 'Sleep Deprivation', styleClass: 'moderate', confirmed: 'yes',
            tooltip: { evidence: 'Moderate', stat: 'Dose-dependent arousal increase', citation: 'Multiple sleep studies', mechanism: 'Fragmented sleep architecture increases microarousal frequency' } } },

        // ── EXTERNAL FACTORS ──
        { data: { id: 'GENETICS', label: 'Genetics\n21-50% heritable', styleClass: 'moderate', confirmed: 'inactive',
            tooltip: { evidence: 'Moderate (twin studies)', stat: '21-50% heritability', citation: 'Hublin 1998; Abe 2012', mechanism: 'Polygenic predisposition to arousal threshold and motor pattern generation' } } },
        { data: { id: 'SSRI', label: 'SSRIs & Meds', styleClass: 'preliminary', confirmed: 'inactive',
            tooltip: { evidence: 'Moderate (systematic review)', stat: '~24% risk vs 15% baseline', citation: 'Garrett 2018, PMC5914744', mechanism: 'Serotonergic suppression of dopaminergic inhibition of motor patterns' } } },
        { data: { id: 'CAFFEINE', label: 'Caffeine\n1.5x odds', styleClass: 'preliminary', confirmed: 'external',
            tooltip: { evidence: 'Preliminary (observational)', stat: '1.5x odds', citation: 'Bertazzo-Silveira 2016, JADA', mechanism: 'Adenosine receptor antagonism increases arousal frequency' } } },
        { data: { id: 'ALCOHOL', label: 'Alcohol\n2x odds', styleClass: 'preliminary', confirmed: 'external',
            tooltip: { evidence: 'Preliminary (observational)', stat: '2x odds', citation: 'Bertazzo-Silveira 2016, JADA', mechanism: 'Rebound sympathetic activation during alcohol metabolism' } } },

        // ── STRESS MECHANISMS ──
        { data: { id: 'CORTISOL', label: 'Cortisol ↑\nSMD 1.10', styleClass: 'moderate', confirmed: 'yes',
            tooltip: { evidence: 'Moderate (meta-analysis)', stat: 'SMD 1.10 (I²=4%, N=854)', citation: 'Fluerasu 2021', mechanism: 'Elevated cortisol shifts autonomic balance toward sympathetic dominance' } } },
        { data: { id: 'CATECHOL', label: 'Catecholamines\n3.2x', styleClass: 'preliminary', confirmed: 'yes',
            tooltip: { evidence: 'Preliminary (N=40)', stat: 'Adrenaline 3.2x elevation', citation: 'Seraidarian 2009', mechanism: 'Catecholamine surge amplifies sympathetic tone and motor excitability' } } },
        { data: { id: 'SYMPATHETIC', label: 'Sympathetic Shift\n-8 min', styleClass: 'mechanism', confirmed: 'yes',
            tooltip: { evidence: 'Moderate', stat: 'Sympathovagal shift -8 min (P≤0.03)', citation: 'Huynh 2006', mechanism: 'Autonomic shift precedes and triggers microarousals' } } },

        // ── REFLUX MECHANISMS ──
        { data: { id: 'AIRWAY_OBS', label: 'Airway Obstruction', styleClass: 'mechanism', confirmed: 'no',
            tooltip: { evidence: 'Mechanism', stat: '85.7% linked to RMMA', citation: 'Saito 2014', mechanism: 'Upper airway collapse creates negative intrathoracic pressure' } } },
        { data: { id: 'NEG_PRESSURE', label: 'Neg. Intrathoracic\nPressure', styleClass: 'mechanism', confirmed: 'no',
            tooltip: { evidence: 'Mechanism', stat: 'N=25', citation: 'Kuribayashi 2010', mechanism: 'Negative pressure gradient triggers transient lower esophageal sphincter relaxation' } } },
        { data: { id: 'TLESR', label: 'TLESR', styleClass: 'mechanism', confirmed: 'no',
            tooltip: { evidence: 'Mechanism', stat: 'Primary reflux mechanism', citation: 'Kuribayashi 2010', mechanism: 'Transient LES relaxation allows gastric acid into esophagus' } } },
        { data: { id: 'ACID', label: 'Acid Contact\n(Ohmure RCT)', styleClass: 'mechanism', confirmed: 'yes',
            tooltip: { evidence: 'Robust (RCT)', stat: 'Acid infusion induced RMMA (N=12)', citation: 'Ohmure 2011 RCT', mechanism: 'Esophageal acid contact activates vagal afferents triggering protective RMMA' } } },
        { data: { id: 'VAGAL', label: 'Vagal Afferents', styleClass: 'mechanism', confirmed: 'yes',
            tooltip: { evidence: 'Mechanism', stat: 'Afferent signaling pathway', citation: 'Ohmure 2011', mechanism: 'Vagal afferent firing from acid contact triggers brainstem arousal' } } },
        { data: { id: 'PEPSIN', label: 'Pepsin\npH<4 reactivation', styleClass: 'mechanism', confirmed: 'yes',
            tooltip: { evidence: 'Mechanism', stat: 'Active at pH<4', citation: 'Johnston 2007', mechanism: 'Pepsin reactivation in saliva causes tissue damage at low pH' } } },

        // ── NEUROCHEMISTRY ──
        { data: { id: 'GABA_DEF', label: 'GABA Deficit\nP=.003 / P=.011', styleClass: 'preliminary', confirmed: 'no',
            tooltip: { evidence: 'Preliminary (small N)', stat: 'DLPFC P=.003 (N=17); brainstem P=.011 (N=24)', citation: 'Dharmadhikari 2015; Fan 2017', mechanism: 'Reduced GABAergic inhibition lowers threshold for RMMA generation' } } },
        { data: { id: 'DOPAMINE', label: 'Dopamine\nL-dopa -20-30%', styleClass: 'moderate', confirmed: 'no',
            tooltip: { evidence: 'Moderate', stat: 'L-dopa reduced RMMA 20-30% (P<.001, N=10)', citation: 'Lobbezoo 1997', mechanism: 'Dopaminergic modulation of basal ganglia motor circuits affects RMMA' } } },
        { data: { id: 'MG_DEF', label: 'Mg Depletion\nPPI OR 1.66', styleClass: 'preliminary', confirmed: 'no',
            tooltip: { evidence: 'Preliminary', stat: 'PPI→Mg deficit OR 1.66 (N=95,205)', citation: 'Markovits 2014', mechanism: 'Magnesium is a GABA receptor cofactor; depletion impairs inhibitory tone' } } },
        { data: { id: 'VIT_D', label: 'Vit D Deficit\nOR 6.66', styleClass: 'preliminary', confirmed: 'yes',
            tooltip: { evidence: 'Preliminary', stat: 'OR 6.66 (N=100)', citation: 'Alkhatatbeh 2021', mechanism: 'Vitamin D deficiency affects neuromuscular function and sleep quality' } } },

        // ── CENTRAL EVENTS ──
        { data: { id: 'MICRO', label: 'Microarousal\n79% precede RMMA', styleClass: 'robust', confirmed: 'yes',
            tooltip: { evidence: 'Robust (replicated)', stat: '79% of RMMA preceded by EEG arousal, -4s lag (N=20)', citation: 'Kato 2001', mechanism: 'Cortical microarousals trigger brainstem motor pattern generators' } } },
        { data: { id: 'RMMA', label: 'RMMA / Sleep Bruxism\n100% evoked vs 12.5%', styleClass: 'robust', confirmed: 'yes',
            tooltip: { evidence: 'Robust (replicated)', stat: '100% evoked in SB vs 12.5% controls (N=16)', citation: 'Kato 2003', mechanism: 'Rhythmic masticatory muscle activity is the core bruxism motor event' } } },

        // ── SALIVARY CLEARANCE ──
        { data: { id: 'SALIVA', label: 'Salivary Clearance\n6.9 vs 12.6 min', styleClass: 'mechanism', confirmed: 'yes',
            tooltip: { evidence: 'Moderate', stat: '100% pH<4 episodes = RMMA + swallowing (N=20)', citation: 'Miyawaki 2003', mechanism: 'RMMA-induced salivation provides acid buffering and esophageal clearance' } } },

        // ── STRUCTURAL DAMAGE & SENSITIZATION ──
        { data: { id: 'TMD', label: 'TMD / Jaw Damage\nOR 2.25', styleClass: 'robust', confirmed: 'yes',
            tooltip: { evidence: 'Robust (meta-analysis)', stat: 'OR 2.25 (95% CI 1.94-2.56)', citation: 'Mortazavi 2023', mechanism: 'Repetitive RMMA forces cause TMJ disc displacement and joint damage' } } },
        { data: { id: 'FHP', label: 'Forward Head Posture\nEMG F=13.7', styleClass: 'moderate', confirmed: 'yes',
            tooltip: { evidence: 'Moderate', stat: 'Masseter EMG F=13.7 (P<.001, N=25)', citation: 'Ballenberger 2012', mechanism: 'Forward head posture increases masseter activation and TMJ loading' } } },
        { data: { id: 'CERVICAL', label: 'Cervical Dysfunction\nOR 2.8-5.1', styleClass: 'moderate', confirmed: 'yes',
            tooltip: { evidence: 'Moderate (dose-response)', stat: 'OR 2.8-5.1 (N=616)', citation: 'Wiesinger 2009', mechanism: 'Cervical dysfunction feeds into trigeminocervical complex sensitization' } } },
        { data: { id: 'HYOID', label: 'Hyoid Displacement', styleClass: 'preliminary', confirmed: 'yes',
            tooltip: { evidence: 'Preliminary', stat: 'Clinical observation', citation: 'Diagnostic imaging studies', mechanism: 'TMD-related hyoid displacement contributes to globus sensation' } } },
        { data: { id: 'CS', label: 'Trigeminocervical Sens.\n28/36 elevated', styleClass: 'robust', confirmed: 'yes',
            tooltip: { evidence: 'Robust (large N)', stat: '28/36 pain measures elevated (N=1818)', citation: 'Greenspan 2011 (OPPERA)', mechanism: 'Central sensitization amplifies pain signals from trigeminal and cervical inputs' } } },
        { data: { id: 'WINDUP', label: 'Temporal Summation\nP<.001', styleClass: 'mechanism', confirmed: 'yes',
            tooltip: { evidence: 'Mechanism', stat: 'P<.001', citation: 'Zhang 2017', mechanism: 'Repeated stimulation causes progressive pain amplification (wind-up)' } } },

        // ── SYMPTOMS ──
        { data: { id: 'GRINDING', label: 'Grinding / Clenching', styleClass: 'symptom', confirmed: 'yes',
            tooltip: { evidence: 'Symptom', stat: 'Primary clinical presentation', citation: 'Clinical', mechanism: 'Audible/visible nocturnal tooth grinding and daytime clenching' } } },
        { data: { id: 'TOOTH', label: 'Tooth Wear', styleClass: 'symptom', confirmed: 'yes',
            tooltip: { evidence: 'Symptom', stat: 'Cumulative mechanical damage', citation: 'Clinical', mechanism: 'Repetitive grinding forces cause enamel attrition and fractures' } } },
        { data: { id: 'HEADACHES', label: 'Morning Headaches', styleClass: 'symptom', confirmed: 'yes',
            tooltip: { evidence: 'Symptom', stat: 'Common morning presentation', citation: 'Clinical', mechanism: 'Nocturnal masseter/temporalis contraction causes tension-type headaches' } } },
        { data: { id: 'EAR', label: 'Ear Fullness\n74.8% in TMD', styleClass: 'symptom', confirmed: 'yes',
            tooltip: { evidence: 'Moderate', stat: '74.8% prevalence in TMD patients', citation: 'Porto De Toledo 2017', mechanism: 'TMJ proximity to ear canal causes referred aural symptoms via V3 nerve' } } },
        { data: { id: 'NECK_TIGHTNESS', label: 'Neck Tightness\n& Spasm', styleClass: 'symptom', confirmed: 'yes',
            tooltip: { evidence: 'Symptom', stat: 'Chronic neck muscle tightness', citation: 'Clinical', mechanism: 'Cervical muscle tension and spasm, especially affecting swallowing' } } },
        { data: { id: 'GLOBUS', label: 'Globus / Throat\n45% prevalence', styleClass: 'symptom', confirmed: 'yes',
            tooltip: { evidence: 'Moderate', stat: '45% prevalence', citation: 'Clinical series', mechanism: 'Hyoid displacement + pepsin damage = persistent globus sensation' } } },

        // ── INTERVENTIONS ──
        // Each intervention targets a mechanism node; ELK places them based on edges.

        { data: { id: 'OSA_TX', label: 'Sleep Apnea Tx\nCPAP / MAD', styleClass: 'intervention',
            tooltip: { evidence: 'Moderate-High (RCTs)', stat: 'Significant bruxism reduction', citation: 'PubMed 2022 RCT', mechanism: 'Eliminates apnea-driven microarousals that trigger RMMA' } } },
        { data: { id: 'SSRI_TX', label: 'SSRI Review\n+ Buspirone', styleClass: 'intervention',
            tooltip: { evidence: 'Moderate (systematic review)', stat: '~24% vs 15% baseline risk', citation: 'Garrett 2018, PMC5914744', mechanism: 'Medication review addresses serotonergic bruxism; buspirone 5-30mg may help' } } },
        { data: { id: 'MORNING_FAST_TX', label: 'Delay Breakfast\n1.5-2h', styleClass: 'intervention',
            tooltip: { evidence: 'Low-Moderate', stat: 'LPR protocol component', citation: 'ENT clinical protocols', mechanism: 'Reduces morning reflux surge by allowing esophageal recovery' } } },
        { data: { id: 'REFLUX_DIET_TX', label: 'Reflux Diet\n& Avoidance', styleClass: 'intervention',
            tooltip: { evidence: 'Moderate', stat: 'Eliminates acid triggers', citation: 'Koufman 2012; ENT protocols', mechanism: 'Dietary modifications remove upstream acid/reflux triggers' } } },
        { data: { id: 'BED_ELEV_TX', label: 'Bed Elevation\n10-25cm', styleClass: 'intervention',
            tooltip: { evidence: 'Moderate', stat: 'Gravity-based clearance', citation: 'GERD treatment guidelines', mechanism: 'Gravity reduces nocturnal acid contact time in supine position' } } },
        { data: { id: 'MINDFULNESS_TX', label: 'Mindfulness\n& Stress Reduction', styleClass: 'intervention',
            tooltip: { evidence: 'Moderate', stat: 'Cortisol reduction pathway', citation: 'Stress reduction meta-analyses', mechanism: 'Breaks hypervigilance cycle and reduces HPA axis activation' } } },
        { data: { id: 'CBT_TX', label: 'CBT\n(Limited SB evidence)', styleClass: 'intervention',
            tooltip: { evidence: 'Low (GRADE: extremely low)', stat: '3 RCTs, 1 showed EMG reduction', citation: 'Japanese Dental Science Review 2022', mechanism: 'Cognitive restructuring addresses stress/anxiety contributors' } } },
        { data: { id: 'NATURE_TX', label: 'Nature Exposure\n20+ min', styleClass: 'intervention',
            tooltip: { evidence: 'Low-Moderate', stat: 'Cortisol reduction', citation: 'Nature exposure studies', mechanism: 'Outdoor exposure reduces cortisol via parasympathetic activation' } } },
        { data: { id: 'SCREENS_TX', label: 'No Screens\n1h before bed', styleClass: 'intervention',
            tooltip: { evidence: 'Moderate', stat: 'Reduces pre-sleep arousal', citation: 'Sleep hygiene meta-analyses', mechanism: 'Eliminates blue light and cognitive stimulation before sleep' } } },
        { data: { id: 'YOGA_TX', label: 'Yoga 3x/wk\nGABA +27%', styleClass: 'intervention',
            tooltip: { evidence: 'Moderate', stat: 'GABA +27% (P=.018)', citation: 'Streeter 2007/2010', mechanism: 'Yoga increases brain GABA levels and reduces cortisol/sympathetic tone' } } },
        { data: { id: 'EXERCISE_TX', label: 'Exercise\n>4h before bed', styleClass: 'intervention',
            tooltip: { evidence: 'Moderate', stat: 'Supports sleep architecture', citation: 'Exercise-sleep meta-analyses', mechanism: 'Reduces cortisol and improves deep sleep proportion' } } },
        { data: { id: 'BREATHING_TX', label: 'Slow Breathing\n4s in / 6-8s out', styleClass: 'intervention',
            tooltip: { evidence: 'Low-Moderate', stat: 'Parasympathetic shift', citation: 'Breathing intervention studies', mechanism: 'Extended exhale activates vagal brake and reduces cortisol' } } },
        { data: { id: 'WARM_SHOWER_TX', label: 'Warm Shower\n40-42°C', styleClass: 'intervention',
            tooltip: { evidence: 'Moderate', stat: 'Meta-analytic support', citation: 'Haghayegh 2019 meta-analysis', mechanism: 'Thermoregulatory vasodilation promotes sleep onset' } } },
        { data: { id: 'PPI_TX', label: 'PPI / Lansoprazole\nOhmure 2016 RCT', styleClass: 'intervention',
            tooltip: { evidence: 'Robust (RCT)', stat: 'Sig. ↓ RMMA (N=12)', citation: 'Ohmure 2016 RCT', mechanism: 'Proton pump inhibitor reduces acid production, breaking reflux→RMMA cycle' } } },
        { data: { id: 'HYDRATION', label: 'Hydration\n3L/day target', styleClass: 'intervention',
            tooltip: { evidence: 'Low-Moderate', stat: 'ENT guidance for LPR', citation: 'Clinical protocols', mechanism: 'Dilutes acid contact time and supports salivary clearance' } } },
        { data: { id: 'TONGUE_TX', label: 'Tongue Posture\nLTTA', styleClass: 'intervention',
            tooltip: { evidence: 'Low-Moderate', stat: 'Clinical experience', citation: 'Orofacial myology protocols', mechanism: 'Prevents clenching habit and improves airway patency' } } },
        { data: { id: 'NEUROSYM_TX', label: 'Nurosym taVNS\n30 min', styleClass: 'intervention',
            tooltip: { evidence: 'Low', stat: 'Neuromodulation', citation: 'taVNS pilot studies', mechanism: 'Transcutaneous vagal nerve stimulation shifts autonomic balance' } } },
        { data: { id: 'MG_SUPP', label: 'Mg Glycinate\n400-600mg', styleClass: 'intervention',
            tooltip: { evidence: 'Moderate (RCT)', stat: 'Improved sleep + cortisol', citation: 'Abbasi 2012 RCT', mechanism: 'Magnesium supplementation restores GABA cofactor and inhibitory tone' } } },
        { data: { id: 'THEANINE_TX', label: 'L-Theanine\n200mg', styleClass: 'intervention',
            tooltip: { evidence: 'Low-Moderate', stat: 'Modest stress reduction in RCTs', citation: 'L-theanine RCTs', mechanism: 'Alpha-amino acid enhances GABA-mediated inhibitory neurotransmission' } } },
        { data: { id: 'GLYCINE_TX', label: 'Glycine\n3g', styleClass: 'intervention',
            tooltip: { evidence: 'Low-Moderate', stat: 'Small RCTs positive', citation: 'Glycine sleep RCTs', mechanism: 'Inhibitory neurotransmitter improves subjective sleep quality' } } },
        { data: { id: 'MULTI_TX', label: 'Multivitamin\nB6/Zn/Mg', styleClass: 'intervention',
            tooltip: { evidence: 'Low-Moderate', stat: 'Cofactor replenishment', citation: 'Nutrient deficiency review 2023', mechanism: 'Replenishes PPI-depleted cofactors supporting GABA synthesis' } } },
        { data: { id: 'VIT_D_TX', label: 'Vitamin D\nSupplementation', styleClass: 'intervention',
            tooltip: { evidence: 'Low-Moderate', stat: 'OR 6.66 deficiency link', citation: 'Alkhatatbeh 2021', mechanism: 'Corrects vitamin D deficiency linked to neuromuscular dysfunction' } } },
        { data: { id: 'BIOFEEDBACK_TX', label: 'EMG Biofeedback\nHaptic alerts', styleClass: 'intervention',
            tooltip: { evidence: 'Moderate (meta-analysis)', stat: 'SMD -0.56 (N=219, P=.001)', citation: 'J Oral Rehabil 2018', mechanism: 'Haptic alerts interrupt RMMA during microarousal window' } } },
        { data: { id: 'JAW_RELAX_TX', label: 'Jaw Relaxation\n& PMR', styleClass: 'intervention',
            tooltip: { evidence: 'Low-Moderate', stat: 'Awake bruxism focus', citation: 'Behavioral intervention studies', mechanism: 'Progressive muscle relaxation releases jaw tension and RMMA drive' } } },
        { data: { id: 'BOTOX_TX', label: 'Botox\nMasseter injection', styleClass: 'intervention',
            tooltip: { evidence: 'Moderate-High (meta-analysis)', stat: 'VAS -4.0; events 5→1.7/h (N=320)', citation: 'Br J Oral Maxillofac Surg 2022', mechanism: 'Botulinum toxin weakens masseter, reducing grinding force and pain' } } },
        { data: { id: 'CIRCADIAN_TX', label: 'Morning Light\n& Routine', styleClass: 'intervention',
            tooltip: { evidence: 'Low-Moderate', stat: 'Circadian anchoring', citation: 'Sleep hygiene literature', mechanism: 'Stabilizes circadian rhythm, reducing arousal instability' } } },
        { data: { id: 'SLEEP_HYG_TX', label: 'Sleep Hygiene\nConsistent schedule', styleClass: 'intervention',
            tooltip: { evidence: 'Low-Moderate', stat: 'Foundational intervention', citation: 'Sleep hygiene guidelines', mechanism: 'Consistent sleep schedule reduces microarousal frequency' } } },
        { data: { id: 'PHYSIO_TX', label: 'Physio Exercises\n3x/day (Rocabado)', styleClass: 'intervention',
            tooltip: { evidence: 'Moderate (RCT)', stat: 'Improved jaw mobility', citation: 'Massage RCT, Frontiers 2022', mechanism: 'Addresses TMD, forward head posture, and cervical dysfunction' } } },
        { data: { id: 'POSTURE_TX', label: 'Posture Check', styleClass: 'intervention',
            tooltip: { evidence: 'Low', stat: 'Theoretical/clinical', citation: 'Postural assessment literature', mechanism: 'Reduces FHP-driven masseter strain and cervical dysfunction' } } },
        { data: { id: 'MASSAGE_TX', label: 'Jaw Massage\n5min 2x/day', styleClass: 'intervention',
            tooltip: { evidence: 'Moderate (RCT)', stat: 'Improved sleep quality & mobility', citation: 'Frontiers in Neurology 2022', mechanism: 'Deep tissue massage improves TMJ mobility and reduces pain' } } },
        { data: { id: 'HEAT_TX', label: 'Heat/Cold\nTherapy', styleClass: 'intervention',
            tooltip: { evidence: 'Low', stat: 'Symptom relief', citation: 'Clinical practice', mechanism: 'Local vasodilation and pain gate modulation for symptom relief' } } },
        { data: { id: 'SPLINT', label: 'Hard Splint\n-80% EMG', styleClass: 'intervention',
            tooltip: { evidence: 'Moderate (Cochrane)', stat: '-80% EMG with hard splint; soft ↑50%', citation: 'Okeson 1987; Cochrane 2007', mechanism: 'Hard acrylic stabilization splint protects teeth and distributes forces' } } },
    ],
    edges: [
        // ── Health Anxiety → Stress ──
        { data: { source: 'HEALTH_ANXIETY', target: 'STRESS', edgeType: 'forward', edgeColor: '#b45309',
            tooltip: 'Health anxiety feeds into stress and hypervigilance cycle' } },

        // ── Stress → HPA axis ──
        { data: { source: 'STRESS', target: 'CORTISOL', label: 'OR 2.07', edgeType: 'forward', edgeColor: '#b45309',
            tooltip: 'Psychological stress activates the HPA axis, elevating cortisol (Chemelo 2020, OR 2.07)' } },
        { data: { source: 'STRESS', target: 'CATECHOL', edgeType: 'forward', edgeColor: '#b45309',
            tooltip: 'Stress drives catecholamine release via sympathoadrenal pathway' } },
        { data: { source: 'CORTISOL', target: 'SYMPATHETIC', edgeType: 'forward', edgeColor: '#b45309',
            tooltip: 'Elevated cortisol shifts autonomic balance toward sympathetic dominance' } },
        { data: { source: 'CATECHOL', target: 'SYMPATHETIC', edgeType: 'forward', edgeColor: '#6b21a8',
            tooltip: 'Catecholamines amplify sympathetic nervous system activity' } },
        { data: { source: 'SYMPATHETIC', target: 'MICRO', edgeType: 'forward', edgeColor: '#374151',
            tooltip: 'Sympathetic shift lowers microarousal threshold during sleep' } },

        // ── OSA / Reflux pathway ──
        { data: { source: 'OSA', target: 'AIRWAY_OBS', edgeType: 'forward', edgeColor: '#b45309',
            tooltip: 'Obstructive sleep apnea causes repeated upper airway collapse' } },
        { data: { source: 'AIRWAY_OBS', target: 'MICRO', label: '85.7% linked', edgeType: 'forward', edgeColor: '#374151',
            tooltip: 'Airway obstruction triggers cortical microarousals (85.7% linked, Saito 2014)' } },
        { data: { source: 'AIRWAY_OBS', target: 'NEG_PRESSURE', edgeType: 'forward', edgeColor: '#374151',
            tooltip: 'Airway obstruction creates negative intrathoracic pressure' } },
        { data: { source: 'NEG_PRESSURE', target: 'TLESR', edgeType: 'forward', edgeColor: '#374151',
            tooltip: 'Negative pressure triggers transient LES relaxation (Kuribayashi 2010)' } },
        { data: { source: 'TLESR', target: 'ACID', edgeType: 'forward', edgeColor: '#374151',
            tooltip: 'TLESR allows gastric acid to reflux into esophagus' } },
        { data: { source: 'OSA', target: 'GERD', label: '62-78% comorbid', edgeType: 'forward', edgeColor: '#b45309',
            tooltip: 'OSA and GERD are highly comorbid (62-78% overlap)' } },
        { data: { source: 'GERD', target: 'ACID', edgeType: 'forward', edgeColor: '#1b4332',
            tooltip: 'GERD produces chronic acid reflux and micro-aspiration' } },
        { data: { source: 'GERD', target: 'PEPSIN', edgeType: 'forward', edgeColor: '#1b4332',
            tooltip: 'GERD causes pepsin reflux into esophagus and larynx' } },
        { data: { source: 'ACID', target: 'VAGAL', label: 'vagal afferents', edgeType: 'forward', edgeColor: '#374151',
            tooltip: 'Esophageal acid contact activates vagal afferent neurons' } },
        { data: { source: 'VAGAL', target: 'MICRO', edgeType: 'forward', edgeColor: '#374151',
            tooltip: 'Vagal afferent firing triggers brainstem-mediated microarousals' } },
        { data: { source: 'STRESS', target: 'GERD', label: 'visceral hypersens.', edgeType: 'forward', edgeColor: '#b45309',
            tooltip: 'Stress increases visceral hypersensitivity to acid exposure' } },

        // ── Other upstream → Arousal ──
        { data: { source: 'GENETICS', target: 'MICRO', edgeType: 'forward', edgeColor: '#b45309',
            tooltip: 'Genetic predisposition affects arousal threshold (21-50% heritable)' } },
        { data: { source: 'SLEEP_DEP', target: 'MICRO', edgeType: 'forward', edgeColor: '#b45309',
            tooltip: 'Sleep deprivation increases microarousal frequency' } },
        { data: { source: 'SSRI', target: 'RMMA', label: '~24% risk', edgeType: 'forward', edgeColor: '#6b21a8',
            tooltip: 'SSRIs suppress dopaminergic inhibition of motor patterns (~24% bruxism risk)' } },
        { data: { source: 'CAFFEINE', target: 'MICRO', edgeType: 'forward', edgeColor: '#6b21a8',
            tooltip: 'Caffeine antagonizes adenosine receptors, increasing arousal (1.5x odds)' } },
        { data: { source: 'ALCOHOL', target: 'MICRO', edgeType: 'forward', edgeColor: '#6b21a8',
            tooltip: 'Alcohol causes rebound sympathetic activation during metabolism (2x odds)' } },

        // ── Neurochemistry → RMMA ──
        { data: { source: 'GABA_DEF', target: 'RMMA', edgeType: 'forward', edgeColor: '#6b21a8',
            tooltip: 'GABA deficit reduces inhibitory control of motor pattern generators' } },
        { data: { source: 'DOPAMINE', target: 'RMMA', edgeType: 'dashed', edgeColor: '#b45309',
            tooltip: 'Dopaminergic dysregulation affects basal ganglia motor circuits (preliminary)' } },
        { data: { source: 'MG_DEF', target: 'GABA_DEF', label: 'GABA cofactor', edgeType: 'forward', edgeColor: '#6b21a8',
            tooltip: 'Magnesium is a GABA receptor cofactor; depletion impairs inhibitory tone' } },
        { data: { source: 'VIT_D', target: 'RMMA', edgeType: 'dashed', edgeColor: '#6b21a8',
            tooltip: 'Vitamin D deficiency linked to neuromuscular dysfunction (OR 6.66, preliminary)' } },

        // ── Arousal chain ──
        { data: { source: 'MICRO', target: 'RMMA', label: '79% precede', edgeType: 'forward', edgeColor: '#1b4332',
            tooltip: '79% of RMMA episodes preceded by EEG microarousal (Kato 2001)' } },

        // ── RMMA → Downstream ──
        { data: { source: 'RMMA', target: 'GRINDING', edgeType: 'forward', edgeColor: '#1b4332',
            tooltip: 'RMMA manifests clinically as nocturnal grinding and clenching' } },
        { data: { source: 'RMMA', target: 'TMD', label: 'OR 2.25', edgeType: 'forward', edgeColor: '#1b4332',
            tooltip: 'Repetitive RMMA forces cause TMJ damage (OR 2.25, Mortazavi 2023)' } },
        { data: { source: 'RMMA', target: 'SALIVA', label: 'periodontal reflex', edgeType: 'forward', edgeColor: '#1b4332',
            tooltip: 'RMMA triggers salivation via periodontal mechanoreceptor reflex' } },
        { data: { source: 'RMMA', target: 'CS', edgeType: 'dashed', edgeColor: '#1b4332',
            tooltip: 'Chronic RMMA may contribute to central sensitization (preliminary)' } },
        { data: { source: 'SALIVA', target: 'GERD', label: 'acid clearance', edgeType: 'forward', edgeColor: '#374151',
            tooltip: 'Increased salivation aids esophageal acid clearance' } },
        { data: { source: 'GRINDING', target: 'TOOTH', edgeType: 'forward', edgeColor: '#1e3a5f',
            tooltip: 'Grinding forces cause progressive tooth enamel wear and fractures' } },
        { data: { source: 'GRINDING', target: 'HEADACHES', edgeType: 'forward', edgeColor: '#1e3a5f',
            tooltip: 'Nocturnal muscle contraction causes morning tension headaches' } },

        // ── Structural damage cascade ──
        { data: { source: 'TMD', target: 'CERVICAL', edgeType: 'forward', edgeColor: '#1b4332',
            tooltip: 'TMD dysfunction propagates to cervical spine via biomechanical chain' } },
        { data: { source: 'TMD', target: 'EAR', label: 'V3 spillover', edgeType: 'forward', edgeColor: '#1b4332',
            tooltip: 'TMJ proximity causes referred ear symptoms via V3 nerve spillover' } },
        { data: { source: 'TMD', target: 'HYOID', edgeType: 'forward', edgeColor: '#1b4332',
            tooltip: 'TMD alters suprahyoid muscle function and hyoid position' } },
        { data: { source: 'TMD', target: 'CS', edgeType: 'forward', edgeColor: '#1b4332',
            tooltip: 'Chronic TMD pain drives trigeminocervical sensitization' } },
        { data: { source: 'FHP', target: 'TMD', label: 'EMG F=13.7', edgeType: 'forward', edgeColor: '#b45309',
            tooltip: 'Forward head posture increases masseter EMG and TMJ loading (F=13.7)' } },
        { data: { source: 'FHP', target: 'HYOID', edgeType: 'forward', edgeColor: '#b45309',
            tooltip: 'FHP displaces hyoid bone anteroinferiorly' } },
        { data: { source: 'CERVICAL', target: 'CS', label: 'TCC convergence', edgeType: 'forward', edgeColor: '#b45309',
            tooltip: 'Cervical afferents converge at trigeminocervical complex (TCC)' } },
        { data: { source: 'CERVICAL', target: 'FHP', edgeType: 'dashed', edgeColor: '#b45309',
            tooltip: 'Cervical dysfunction may promote compensatory forward head posture' } },
        { data: { source: 'HYOID', target: 'GLOBUS', edgeType: 'dashed', edgeColor: '#6b21a8',
            tooltip: 'Hyoid displacement contributes to globus sensation (preliminary)' } },

        // ── Sensitization → Symptoms ──
        { data: { source: 'CS', target: 'WINDUP', edgeType: 'forward', edgeColor: '#1b4332',
            tooltip: 'Central sensitization enables temporal summation (wind-up)' } },
        { data: { source: 'CS', target: 'NECK_TIGHTNESS', label: 'SMD -1.10', edgeType: 'forward', edgeColor: '#1b4332',
            tooltip: 'Central sensitization amplifies pain perception (SMD -1.10)' } },
        { data: { source: 'CS', target: 'GLOBUS', edgeType: 'forward', edgeColor: '#1b4332',
            tooltip: 'Sensitization amplifies pharyngeal sensation (globus)' } },
        { data: { source: 'WINDUP', target: 'NECK_TIGHTNESS', edgeType: 'forward', edgeColor: '#374151',
            tooltip: 'Wind-up phenomenon causes progressive pain amplification' } },
        { data: { source: 'GERD', target: 'GLOBUS', edgeType: 'dashed', edgeColor: '#1b4332',
            tooltip: 'GERD/LPR may contribute to globus sensation (preliminary)' } },
        { data: { source: 'PEPSIN', target: 'GLOBUS', edgeType: 'dashed', edgeColor: '#374151',
            tooltip: 'Pepsin in saliva damages pharyngeal tissue (preliminary)' } },

        // ── Feedback loops (vicious cycles) ──
        { data: { source: 'NECK_TIGHTNESS', target: 'STRESS', label: 'hypervigilance', edgeType: 'feedback', edgeColor: '#ef4444',
            tooltip: 'Chronic pain drives stress and hypervigilance (vicious cycle)' } },
        { data: { source: 'NECK_TIGHTNESS', target: 'SLEEP_DEP', label: 'disrupts sleep', edgeType: 'feedback', edgeColor: '#ef4444',
            tooltip: 'Pain disrupts sleep continuity, worsening bruxism triggers (vicious cycle)' } },
        { data: { source: 'TMD', target: 'STRESS', edgeType: 'feedback', edgeColor: '#ef4444',
            tooltip: 'TMD pain and dysfunction increase stress and anxiety (vicious cycle)' } },
        { data: { source: 'HEADACHES', target: 'STRESS', edgeType: 'feedback', edgeColor: '#ef4444',
            tooltip: 'Morning headaches contribute to stress and worry (vicious cycle)' } },
        { data: { source: 'GLOBUS', target: 'STRESS', label: 'health anxiety', edgeType: 'feedback', edgeColor: '#ef4444',
            tooltip: 'Globus sensation triggers health anxiety (vicious cycle)' } },
        { data: { source: 'SLEEP_DEP', target: 'OSA', edgeType: 'feedback', edgeColor: '#ef4444',
            tooltip: 'Sleep deprivation worsens airway collapsibility (vicious cycle)' } },

        // ── Interventions (existing) ──
        { data: { source: 'PPI_TX', target: 'GERD', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'PPI reduces gastric acid, treating GERD/reflux upstream' } },
        { data: { source: 'PPI_TX', target: 'MG_DEF', label: 'depletes Mg', edgeType: 'dashed', edgeColor: '#065f46',
            tooltip: 'PPI side effect: chronic use depletes magnesium (OR 1.66)' } },
        { data: { source: 'SPLINT', target: 'TOOTH', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Hard occlusal splint protects teeth from grinding damage' } },
        { data: { source: 'MG_SUPP', target: 'GABA_DEF', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Magnesium supplementation restores GABA cofactor levels' } },
        { data: { source: 'YOGA_TX', target: 'GABA_DEF', label: 'GABA +27%', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Yoga increases brain GABA by 27% (Streeter 2007, P=.018)' } },

        // ── Interventions (new) ──
        { data: { source: 'HYDRATION', target: 'ACID', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Hydration dilutes esophageal acid contact' } },
        { data: { source: 'HYDRATION', target: 'SALIVA', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Hydration supports salivary flow for acid clearance' } },
        { data: { source: 'VIT_D_TX', target: 'VIT_D', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Vitamin D supplementation corrects deficiency' } },
        { data: { source: 'MULTI_TX', target: 'MG_DEF', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Multivitamin replenishes PPI-depleted magnesium and cofactors' } },
        { data: { source: 'MORNING_FAST_TX', target: 'GERD', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Delayed breakfast reduces morning reflux episode severity' } },
        { data: { source: 'CIRCADIAN_TX', target: 'SLEEP_DEP', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Morning light anchors circadian rhythm, improving sleep quality' } },
        { data: { source: 'CIRCADIAN_TX', target: 'MICRO', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Circadian stability reduces microarousal frequency' } },
        { data: { source: 'MINDFULNESS_TX', target: 'STRESS', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Mindfulness practice reduces perceived stress and hypervigilance' } },
        { data: { source: 'MINDFULNESS_TX', target: 'CORTISOL', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Regular meditation reduces cortisol levels' } },
        { data: { source: 'PHYSIO_TX', target: 'TMD', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Physical therapy improves TMJ mobility and reduces pain' } },
        { data: { source: 'PHYSIO_TX', target: 'FHP', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Rocabado exercises correct forward head posture' } },
        { data: { source: 'PHYSIO_TX', target: 'CERVICAL', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Cervical exercises address cervical dysfunction' } },
        { data: { source: 'EXERCISE_TX', target: 'SLEEP_DEP', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Regular exercise improves sleep quality and duration' } },
        { data: { source: 'EXERCISE_TX', target: 'CORTISOL', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Exercise reduces chronic cortisol elevation' } },
        { data: { source: 'NATURE_TX', target: 'STRESS', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Nature exposure reduces stress via parasympathetic activation' } },
        { data: { source: 'NATURE_TX', target: 'CORTISOL', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Outdoor exposure lowers cortisol levels' } },
        { data: { source: 'REFLUX_DIET_TX', target: 'GERD', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Dietary modifications eliminate reflux triggers' } },
        { data: { source: 'REFLUX_DIET_TX', target: 'ACID', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Trigger avoidance reduces acid production and reflux episodes' } },
        { data: { source: 'POSTURE_TX', target: 'FHP', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Posture awareness corrects forward head positioning' } },
        { data: { source: 'POSTURE_TX', target: 'CERVICAL', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Improved posture reduces cervical strain' } },
        { data: { source: 'TONGUE_TX', target: 'HYOID', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Correct tongue posture improves hyoid positioning' } },
        { data: { source: 'TONGUE_TX', target: 'AIRWAY_OBS', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Tongue posture improves airway patency' } },
        { data: { source: 'JAW_RELAX_TX', target: 'RMMA', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Jaw relaxation techniques reduce muscle tension and RMMA drive' } },
        { data: { source: 'MASSAGE_TX', target: 'TMD', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Massage improves TMJ mobility (RCT, Frontiers 2022)' } },
        { data: { source: 'MASSAGE_TX', target: 'NECK_TIGHTNESS', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Massage reduces orofacial pain intensity' } },
        { data: { source: 'HEAT_TX', target: 'TMD', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Heat therapy provides local vasodilation and pain relief' } },
        { data: { source: 'HEAT_TX', target: 'NECK_TIGHTNESS', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Heat/cold modulates pain via gate control mechanism' } },
        { data: { source: 'BED_ELEV_TX', target: 'GERD', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Bed elevation uses gravity to reduce nocturnal reflux' } },
        { data: { source: 'BED_ELEV_TX', target: 'ACID', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Elevation reduces acid contact time in supine position' } },
        { data: { source: 'SCREENS_TX', target: 'SLEEP_DEP', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Screen avoidance reduces pre-sleep arousal and improves sleep onset' } },
        { data: { source: 'WARM_SHOWER_TX', target: 'SYMPATHETIC', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Warm bathing shifts autonomic balance toward parasympathetic' } },
        { data: { source: 'NEUROSYM_TX', target: 'VAGAL', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'taVNS stimulates vagal afferents to shift parasympathetic balance' } },
        { data: { source: 'NEUROSYM_TX', target: 'SYMPATHETIC', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Vagal stimulation reduces sympathetic tone' } },
        { data: { source: 'BREATHING_TX', target: 'SYMPATHETIC', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Extended exhale breathing activates vagal brake' } },
        { data: { source: 'BREATHING_TX', target: 'CORTISOL', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Slow breathing reduces cortisol via HPA axis modulation' } },
        { data: { source: 'THEANINE_TX', target: 'GABA_DEF', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'L-theanine enhances GABAergic inhibitory neurotransmission' } },
        { data: { source: 'GLYCINE_TX', target: 'GABA_DEF', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Glycine acts as inhibitory neurotransmitter supporting GABA pathways' } },
        { data: { source: 'BIOFEEDBACK_TX', target: 'RMMA', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'EMG biofeedback interrupts RMMA episodes (SMD -0.56, meta-analysis)' } },
        { data: { source: 'OSA_TX', target: 'OSA', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'CPAP/MAD treats obstructive sleep apnea, eliminating apnea-driven arousals' } },
        { data: { source: 'SSRI_TX', target: 'SSRI', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Medication review + buspirone addresses SSRI-induced bruxism' } },
        { data: { source: 'BOTOX_TX', target: 'RMMA', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Botox weakens masseter, reducing RMMA force (events 5→1.7/h)' } },
        { data: { source: 'BOTOX_TX', target: 'NECK_TIGHTNESS', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Botox reduces orofacial pain (VAS -4.0, meta-analysis)' } },
        { data: { source: 'CBT_TX', target: 'STRESS', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'CBT addresses stress/anxiety contributors to bruxism' } },
        { data: { source: 'SLEEP_HYG_TX', target: 'SLEEP_DEP', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Consistent sleep hygiene improves sleep continuity' } },
        { data: { source: 'SLEEP_HYG_TX', target: 'MICRO', edgeType: 'forward', edgeColor: '#065f46',
            tooltip: 'Good sleep hygiene reduces microarousal triggers' } },
    ]
};

// ═══════════════════════════════════════════════════════════
// CYTOSCAPE STYLE ARRAY
// ═══════════════════════════════════════════════════════════

const CYTOSCAPE_STYLES = [
    // Base node
    {
        selector: 'node',
        style: {
            'label': 'data(label)',
            'text-wrap': 'wrap',
            'text-max-width': '160px',
            'text-valign': 'center',
            'text-halign': 'center',
            'font-size': '11px',
            'color': '#fff',
            'background-color': '#374151',
            'border-width': 2,
            'border-color': '#1f2937',
            'shape': 'round-rectangle',
            'padding': '10px',
            'width': 'label',
            'height': 'label',
        }
    },
    // ── Confirmed status styles ──
    {
        selector: 'node[confirmed="no"]',
        style: { 'opacity': 0.4, 'border-style': 'dashed' }
    },
    {
        selector: 'node[confirmed="inactive"]',
        style: { 'opacity': 0.2, 'border-style': 'dashed' }
    },
    {
        selector: 'node[confirmed="external"]',
        style: { 'opacity': 0.5, 'border-style': 'dotted' }
    },
    // ── Node style classes ──
    {
        selector: 'node[styleClass="robust"]',
        style: { 'background-color': '#1b4332', 'border-color': '#081c15', 'border-width': 3 }
    },
    {
        selector: 'node[styleClass="moderate"]',
        style: { 'background-color': '#b45309', 'border-color': '#78350f', 'border-width': 2 }
    },
    {
        selector: 'node[styleClass="preliminary"]',
        style: { 'background-color': '#6b21a8', 'border-color': '#4c1d95', 'border-width': 2 }
    },
    {
        selector: 'node[styleClass="symptom"]',
        style: { 'background-color': '#1e3a5f', 'border-color': '#0f172a', 'border-width': 2 }
    },
    {
        selector: 'node[styleClass="mechanism"]',
        style: { 'background-color': '#374151', 'border-color': '#1f2937', 'border-width': 2 }
    },
    {
        selector: 'node[styleClass="intervention"]',
        style: { 'background-color': '#065f46', 'color': '#d1fae5', 'border-color': '#047857', 'border-width': 2, 'border-style': 'dashed' }
    },
    // Group label nodes (oval mode only)
    {
        selector: 'node[styleClass="groupLabel"]',
        style: {
            'background-color': 'rgba(30, 41, 59, 0.85)',
            'background-opacity': 1,
            'border-width': 1,
            'border-color': 'rgba(100, 116, 139, 0.25)',
            'border-style': 'solid',
            'shape': 'round-rectangle',
            'label': 'data(label)',
            'text-valign': 'center',
            'text-halign': 'center',
            'font-size': '11px',
            'font-weight': '700',
            'color': 'rgba(148, 163, 184, 0.8)',
            'text-transform': 'uppercase',
            'width': 'label',
            'height': 'label',
            'padding': '6px',
            'events': 'no',
            'z-index': 0,
        }
    },
    // ── Base edge (data-driven coloring) ──
    {
        selector: 'edge',
        style: {
            'width': 1,
            'line-color': 'data(edgeColor)',
            'target-arrow-color': 'data(edgeColor)',
            'target-arrow-shape': 'triangle',
            'curve-style': 'bezier',
            'arrow-scale': 0.7,
            'opacity': 0.6,
            'font-size': '8px',
            'color': '#94a3b8',
            'text-background-color': '#1a1a2e',
            'text-background-opacity': 0.9,
            'text-background-padding': '2px',
        }
    },
    // Fallback for edges without edgeColor
    {
        selector: 'edge:not([edgeColor])',
        style: { 'line-color': '#888', 'target-arrow-color': '#888' }
    },
    // Edge labels hidden by default — shown on hover via tooltip
    {
        selector: 'edge[label]',
        style: { 'label': '' }
    },
    // Dashed edges (preliminary evidence)
    {
        selector: 'edge[edgeType="dashed"]',
        style: { 'line-style': 'dashed', 'opacity': 0.45 }
    },
    // Feedback loop edges (red dashed) — most prominent
    {
        selector: 'edge[edgeType="feedback"]',
        style: {
            'line-style': 'dashed',
            'line-color': '#ef4444',
            'target-arrow-color': '#ef4444',
            'width': 1.5,
            'opacity': 0.8,
        }
    },
    // ── Node/edge hover highlight ──
    {
        selector: 'node.hover-highlight',
        style: { 'border-width': 3, 'border-color': '#60a5fa', 'z-index': 999 }
    },
    {
        selector: 'edge.hover-highlight',
        style: { 'opacity': 1, 'width': 2, 'z-index': 999, 'label': 'data(label)' }
    },
    {
        selector: 'node.hover-neighbor',
        style: { 'border-width': 2, 'border-color': '#60a5fa', 'z-index': 998 }
    },
    {
        selector: 'node.hover-dimmed',
        style: { 'opacity': 0.25 }
    },
    {
        selector: 'edge.hover-dimmed',
        style: { 'opacity': 0.08 }
    },
    // ── Intervention highlight system ──
    // Baseline dim: mechanism nodes/edges when interventions visible
    { selector: 'node.tx-dimmed', style: { opacity: 0.4 } },
    { selector: 'edge.tx-dimmed', style: { opacity: 0.15 } },
    // Deep dim: everything not highlighted during hover/pin
    { selector: 'node.tx-deep-dimmed', style: { opacity: 0.08 } },
    { selector: 'edge.tx-deep-dimmed', style: { opacity: 0.05 } },
    // Highlighted intervention node
    { selector: 'node.tx-highlighted', style: { opacity: 1, 'border-width': 3, 'border-color': '#38bdf8', 'z-index': 999 } },
    // Highlighted intervention edge
    { selector: 'edge.tx-highlighted', style: { opacity: 1, width: 2.5, 'z-index': 999 } },
    // Highlighted target node
    { selector: 'node.tx-target-highlighted', style: { opacity: 1, 'border-width': 2, 'border-color': '#38bdf8', 'z-index': 998 } },
    // Pinned intervention node (amber border)
    { selector: 'node.tx-pinned', style: { 'border-width': 3, 'border-color': '#f59e0b', 'z-index': 999 } },
];

// ═══════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════

const GRAPH_CONFIGS = [
    { containerId: 'causal-graph', cyContainerId: 'causal-graph-cy' },
    { containerId: 'causal-graph-research', cyContainerId: 'causal-graph-research-cy' },
    { containerId: 'causal-graph-experiments', cyContainerId: 'causal-graph-experiments-cy' },
];

let currentGraphData = null;
let isEditMode = false;
let elkRegistered = false;
let showInterventions = false; // Interventions hidden by default
let pinnedInterventions = new Set(); // Pinned intervention node IDs for highlight persistence

// Cytoscape instance tracking (container ID string → cy instance)
const cyInstances = new Map();

// Tooltip element (shared singleton)
let tooltipEl = null;

// ═══════════════════════════════════════════════════════════
// INIT
// ═══════════════════════════════════════════════════════════

export function initCausalEditor(interventions, onFilter) {
    // Register ELK extension with Cytoscape (once)
    if (!elkRegistered && window.cytoscape && window.cytoscapeElk) {
        window.cytoscape.use(window.cytoscapeElk);
        elkRegistered = true;
    }

    // Init tooltip element
    initTooltip();

    // Load saved diagram or use default
    const saved = storage.getDiagram();
    if (saved && saved.graphData && Array.isArray(saved.graphData.nodes)) {
        currentGraphData = saved.graphData;
    } else {
        currentGraphData = structuredClone(DEFAULT_GRAPH_DATA);
    }

    // Initialize all graph containers
    GRAPH_CONFIGS.forEach(config => {
        const container = document.getElementById(config.containerId);
        if (container) {
            addEditControls(config.containerId);
            renderGraph(config);
        }
    });
}

// ═══════════════════════════════════════════════════════════
// TOOLTIP
// ═══════════════════════════════════════════════════════════

function initTooltip() {
    if (tooltipEl) return;
    tooltipEl = document.createElement('div');
    tooltipEl.className = 'cy-tooltip';
    tooltipEl.style.display = 'none';
    document.body.appendChild(tooltipEl);
}

function attachTooltipHandlers(cy, container) {
    cy.on('mouseover', 'node', (event) => {
        const node = event.target;
        const sc = node.data('styleClass');

        // Show tooltip
        const tooltip = node.data('tooltip');
        if (tooltip) {
            showTooltip(event, container, buildNodeTooltipHtml(node.data('label'), tooltip));
        }

        // Neighborhood highlight (skip for interventions when tx mode is active, and for labels)
        if (sc === 'groupLabel') return;
        if (sc === 'intervention' && showInterventions) return;

        cy.batch(() => {
            cy.elements().addClass('hover-dimmed');
            cy.nodes('[styleClass="groupLabel"]').removeClass('hover-dimmed');
            node.removeClass('hover-dimmed').addClass('hover-highlight');
            const connected = node.connectedEdges();
            connected.removeClass('hover-dimmed').addClass('hover-highlight');
            connected.connectedNodes().removeClass('hover-dimmed').addClass('hover-neighbor');
            node.removeClass('hover-neighbor').addClass('hover-highlight');
        });
    });

    cy.on('mouseover', 'edge', (event) => {
        const edge = event.target;
        const tooltipText = edge.data('tooltip');
        if (!tooltipText) return;
        showTooltip(event, container, buildEdgeTooltipHtml(
            edge.data('source'), edge.data('target'), tooltipText, edge.data('label')
        ));
    });

    cy.on('mouseout', 'node, edge', () => {
        hideTooltip();
        cy.batch(() => {
            cy.elements().removeClass('hover-dimmed hover-highlight hover-neighbor');
        });
    });

    cy.on('pan zoom', () => {
        hideTooltip();
    });
}

function showTooltip(event, container, html) {
    if (!tooltipEl) initTooltip();
    tooltipEl.innerHTML = html;
    tooltipEl.style.display = 'block';

    const rect = container.getBoundingClientRect();
    let x = rect.left + event.renderedPosition.x + 12;
    let y = rect.top + event.renderedPosition.y - 12;

    // Measure after content is set
    const tw = tooltipEl.offsetWidth;
    const th = tooltipEl.offsetHeight;

    // Clamp to viewport
    if (x + tw > window.innerWidth - 8) x = window.innerWidth - tw - 8;
    if (y + th > window.innerHeight - 8) y = window.innerHeight - th - 8;
    if (x < 8) x = 8;
    if (y < 8) y = 8;

    tooltipEl.style.left = x + 'px';
    tooltipEl.style.top = y + 'px';
}

function hideTooltip() {
    if (tooltipEl) tooltipEl.style.display = 'none';
}

function buildNodeTooltipHtml(label, tooltip) {
    const cleanLabel = (label || '').split('\n')[0];
    let html = `<div class="cy-tooltip-title">${escapeHtml(cleanLabel)}</div>`;
    if (tooltip.evidence) {
        html += `<div class="cy-tooltip-row"><span class="cy-tooltip-label">Evidence:</span> ${escapeHtml(tooltip.evidence)}</div>`;
    }
    if (tooltip.stat) {
        html += `<div class="cy-tooltip-row"><span class="cy-tooltip-label">Stat:</span> ${escapeHtml(tooltip.stat)}</div>`;
    }
    if (tooltip.citation) {
        html += `<div class="cy-tooltip-row"><span class="cy-tooltip-label">Citation:</span> ${escapeHtml(tooltip.citation)}</div>`;
    }
    if (tooltip.mechanism) {
        html += `<div class="cy-tooltip-row"><span class="cy-tooltip-label">Mechanism:</span> ${escapeHtml(tooltip.mechanism)}</div>`;
    }
    return html;
}

function buildEdgeTooltipHtml(source, target, tooltipText, label) {
    let html = `<div class="cy-tooltip-title">${escapeHtml(source)} → ${escapeHtml(target)}</div>`;
    if (label) {
        html += `<div class="cy-tooltip-row"><span class="cy-tooltip-label">Stat:</span> ${escapeHtml(label)}</div>`;
    }
    html += `<div class="cy-tooltip-row">${escapeHtml(tooltipText)}</div>`;
    return html;
}

// ═══════════════════════════════════════════════════════════
// LEGEND
// ═══════════════════════════════════════════════════════════

function addLegend(container, interventionsVisible) {
    // Place legend outside graph canvas, in the parent container
    const parent = container.parentElement;
    const existing = parent.querySelector('.graph-legend');
    if (existing) existing.remove();

    const legend = document.createElement('div');
    legend.className = 'graph-legend';
    legend.innerHTML = `
        <div class="legend-section">
            <div class="legend-row"><span class="legend-swatch" style="background:#1b4332;border:2px solid #081c15"></span> Robust</div>
            <div class="legend-row"><span class="legend-swatch" style="background:#b45309;border:2px solid #78350f"></span> Moderate</div>
            <div class="legend-row"><span class="legend-swatch" style="background:#6b21a8;border:2px solid #4c1d95"></span> Preliminary</div>
            <div class="legend-row"><span class="legend-swatch" style="background:#1e3a5f;border:2px solid #0f172a"></span> Symptom</div>
            <div class="legend-row"><span class="legend-swatch" style="background:#374151;border:2px solid #1f2937"></span> Mechanism</div>
            <div class="legend-row"><span class="legend-swatch" style="background:#065f46;border:2px solid #047857;border-style:dashed"></span> Intervention</div>
        </div>
        <div class="legend-section">
            <div class="legend-row"><span class="legend-swatch" style="background:#374151;border:2px solid #1f2937;opacity:1"></span> Confirmed</div>
            <div class="legend-row"><span class="legend-swatch" style="background:#374151;border:2px dashed #1f2937;opacity:0.4"></span> Unconfirmed</div>
            <div class="legend-row"><span class="legend-swatch" style="background:#374151;border:2px dashed #1f2937;opacity:0.2"></span> Inactive</div>
        </div>
        <div class="legend-section">
            <div class="legend-row"><span class="legend-line" style="background:#b45309"></span> Source-colored</div>
            <div class="legend-row"><span class="legend-line legend-line-dashed" style="border-color:#6b21a8"></span> Dashed (prelim)</div>
            <div class="legend-row"><span class="legend-line legend-line-dashed" style="border-color:#ef4444"></span> Feedback (red)</div>
        </div>
        ${interventionsVisible ? '<div class="legend-section"><div class="legend-hint">Hover intervention to highlight &middot; Click to pin</div></div>' : ''}
    `;

    parent.appendChild(legend);
}

// ═══════════════════════════════════════════════════════════
// EDIT CONTROLS
// ═══════════════════════════════════════════════════════════

function addEditControls(containerId) {
    const container = document.getElementById(containerId);
    if (!container) return;
    if (container.querySelector('.graph-controls')) return;

    const controls = document.createElement('div');
    controls.className = 'graph-controls';
    controls.dataset.forGraph = containerId;
    controls.innerHTML = `
        <button class="graph-edit-btn" title="Edit diagram">✏️ Edit</button>
        <button class="graph-save-btn hidden" title="Save changes">✓ Save</button>
        <button class="graph-cancel-btn hidden" title="Cancel">✗ Cancel</button>
        <button class="graph-reset-btn hidden" title="Reset to default">↺ Reset</button>
    `;
    container.insertBefore(controls, container.firstChild);

    controls.querySelector('.graph-edit-btn').addEventListener('click', () => enterEditMode(containerId));
    controls.querySelector('.graph-save-btn').addEventListener('click', () => saveEdit(containerId));
    controls.querySelector('.graph-cancel-btn').addEventListener('click', () => cancelEdit(containerId));
    controls.querySelector('.graph-reset-btn').addEventListener('click', () => resetDiagram(containerId));
}

// ═══════════════════════════════════════════════════════════
// EDIT MODE
// ═══════════════════════════════════════════════════════════

function enterEditMode(containerId) {
    isEditMode = true;
    const container = document.getElementById(containerId);
    const config = GRAPH_CONFIGS.find(c => c.containerId === containerId);

    const controls = container.querySelector('.graph-controls');
    if (controls) {
        controls.querySelector('.graph-edit-btn').classList.add('hidden');
        controls.querySelector('.graph-save-btn').classList.remove('hidden');
        controls.querySelector('.graph-cancel-btn').classList.remove('hidden');
        controls.querySelector('.graph-reset-btn').classList.remove('hidden');
    }

    container.classList.add('edit-mode');

    // Destroy Cytoscape instance
    destroyCyInstance(config.cyContainerId);

    const cyContainer = document.getElementById(config.cyContainerId);
    const prettyJson = JSON.stringify(currentGraphData, null, 2);

    cyContainer.innerHTML = `
        <div class="graph-editor">
            <textarea class="graph-textarea" spellcheck="false">${escapeHtml(prettyJson)}</textarea>
            <div class="graph-preview" id="${config.cyContainerId}-preview"></div>
        </div>
    `;

    const textarea = container.querySelector('.graph-textarea');
    let previewTimeout = null;

    textarea.addEventListener('input', () => {
        clearTimeout(previewTimeout);
        previewTimeout = setTimeout(() => {
            renderPreview(textarea.value, `${config.cyContainerId}-preview`);
        }, 600);
    });

    // Initial preview
    renderPreview(prettyJson, `${config.cyContainerId}-preview`);
}

function renderPreview(jsonText, previewId) {
    const previewEl = document.getElementById(previewId);
    if (!previewEl) return;

    // Destroy previous preview instance
    destroyCyInstance(previewId);

    try {
        const graphData = JSON.parse(jsonText);
        if (!graphData.nodes || !graphData.edges) throw new Error('Missing nodes or edges array');

        createCyInstance(previewId, graphData, true);
        previewEl.classList.remove('error');
    } catch (error) {
        previewEl.innerHTML = `<div class="preview-error">JSON error: ${error.message}</div>`;
        previewEl.classList.add('error');
    }
}

function saveEdit(containerId) {
    const container = document.getElementById(containerId);
    const textarea = container.querySelector('.graph-textarea');

    if (textarea) {
        try {
            const parsed = JSON.parse(textarea.value);
            if (parsed.nodes && parsed.edges) {
                currentGraphData = parsed;
                storage.saveDiagram({ graphData: currentGraphData });
            }
        } catch (e) {
            // Invalid JSON — don't save
        }
    }

    exitEditMode(containerId);
    renderAllGraphs();
}

function cancelEdit(containerId) {
    exitEditMode(containerId);
    const config = GRAPH_CONFIGS.find(c => c.containerId === containerId);
    if (config) renderGraph(config);
}

function exitEditMode(containerId) {
    isEditMode = false;
    const container = document.getElementById(containerId);
    const controls = container.querySelector('.graph-controls');
    if (controls) {
        controls.querySelector('.graph-edit-btn').classList.remove('hidden');
        controls.querySelector('.graph-save-btn').classList.add('hidden');
        controls.querySelector('.graph-cancel-btn').classList.add('hidden');
        controls.querySelector('.graph-reset-btn').classList.add('hidden');
    }
    container.classList.remove('edit-mode');
}

function resetDiagram(containerId) {
    if (confirm('Reset to default diagram?')) {
        currentGraphData = structuredClone(DEFAULT_GRAPH_DATA);
        storage.clearDiagram();

        const container = document.getElementById(containerId);
        const textarea = container.querySelector('.graph-textarea');
        if (textarea) {
            textarea.value = JSON.stringify(currentGraphData, null, 2);
            const config = GRAPH_CONFIGS.find(c => c.containerId === containerId);
            if (config) renderPreview(textarea.value, `${config.cyContainerId}-preview`);
        }
    }
}

// ═══════════════════════════════════════════════════════════
// CYTOSCAPE INSTANCE MANAGEMENT
// ═══════════════════════════════════════════════════════════

function createCyInstance(containerId, graphData, isPreview = false) {
    const container = document.getElementById(containerId);
    if (!container) return null;

    // Destroy previous instance
    destroyCyInstance(containerId);

    // Build node set, filtering interventions if hidden
    const interventionIds = new Set();
    const filteredNodes = graphData.nodes.filter(n => {
        if (n.data.styleClass === 'intervention') {
            interventionIds.add(n.data.id);
            return showInterventions;
        }
        return true;
    });

    // Filter edges: remove any edge where source or target is a hidden intervention
    const filteredEdges = graphData.edges.filter(e => {
        if (!showInterventions) {
            if (interventionIds.has(e.data.source) || interventionIds.has(e.data.target)) {
                return false;
            }
        }
        return true;
    });

    // Build Cytoscape elements, tagging intervention edges
    const elements = [
        ...filteredNodes.map(n => ({ group: 'nodes', data: { ...n.data } })),
        ...filteredEdges.map(e => {
            const edgeData = { ...e.data };
            if (interventionIds.has(edgeData.source) || interventionIds.has(edgeData.target)) {
                edgeData.isInterventionEdge = true;
            }
            return { group: 'edges', data: edgeData };
        }),
        // Inject tier label nodes for main (non-preview) graphs
        ...(!isPreview ? Object.entries(TIER_LABELS).map(([tier, label]) => ({
            group: 'nodes',
            data: { id: `_tier_${tier}`, label, styleClass: 'groupLabel', tier: parseInt(tier) },
        })) : []),
    ];

    const cy = window.cytoscape({
        container: container,
        elements: elements,
        style: CYTOSCAPE_STYLES,
        userZoomingEnabled: false,  // Custom wheel handler
        userPanningEnabled: true,
        boxSelectionEnabled: false,
        selectionType: 'single',
        minZoom: 0.1,
        maxZoom: 10,
    });

    cyInstances.set(containerId, cy);

    // Layout: tiered columns for main graphs, ELK for edit-mode preview
    if (isPreview) {
        runElkLayout(cy);
    } else {
        runTieredLayout(cy, container);
    }

    // Attach custom wheel handler, zoom controls, tooltips, legend
    attachWheelHandler(container, cy);
    addZoomControls(container, cy);
    attachTooltipHandlers(cy, container);
    addLegend(container, showInterventions);

    // If interventions are visible, apply dimming and hover/click handlers
    if (showInterventions) {
        applyInterventionDimming(cy);
        attachInterventionHandlers(cy);
    }

    return cy;
}

function destroyCyInstance(containerId) {
    const cy = cyInstances.get(containerId);
    if (cy) {
        cy.destroy();
        cyInstances.delete(containerId);
    }
    const container = document.getElementById(containerId);
    if (container) {
        if (container._wheelHandler) {
            container.removeEventListener('wheel', container._wheelHandler);
            container._wheelHandler = null;
        }
        const controls = container.querySelector('.panzoom-controls');
        if (controls) controls.remove();
        const legend = container.parentElement?.querySelector('.graph-legend');
        if (legend) legend.remove();
    }
}

// ═══════════════════════════════════════════════════════════
// TIERED COLUMN LAYOUT (preset positions)
// ═══════════════════════════════════════════════════════════

// Tier assignment for every non-intervention node
const NODE_TIERS = {
    // Tier 0: INPUTS (leftmost column)
    STRESS: 0, HEALTH_ANXIETY: 0, GERD: 0, FHP: 0, VIT_D: 0, SLEEP_DEP: 0,
    OSA: 0, GENETICS: 0, SSRI: 0, CAFFEINE: 0, ALCOHOL: 0,

    // Tier 1: IMMEDIATE MECHANISMS
    CORTISOL: 1, CATECHOL: 1, SYMPATHETIC: 1,
    AIRWAY_OBS: 1, MG_DEF: 1,

    // Tier 2: INTERMEDIATE MECHANISMS / PATHWAYS
    NEG_PRESSURE: 2, TLESR: 2, ACID: 2,
    GABA_DEF: 2, DOPAMINE: 2, VAGAL: 2, PEPSIN: 2,

    // Tier 3: CENTRAL EVENTS
    MICRO: 3, RMMA: 3,

    // Tier 4: CONSEQUENCES & DOWNSTREAM (rightmost column)
    GRINDING: 4, TOOTH: 4, TMD: 4, HEADACHES: 4,
    EAR: 4, NECK_TIGHTNESS: 4, GLOBUS: 4,
    SALIVA: 4, CERVICAL: 4, CS: 4, WINDUP: 4, HYOID: 4,
};

const TIER_LABELS = {
    0: 'INPUTS',
    1: 'MECHANISMS',
    2: 'PATHWAYS',
    3: 'CENTRAL',
    4: 'CONSEQUENCES',
};

const NUM_TIERS = 5;

function computeTieredPositions(cy, width, height) {
    const padX = 80;
    const padY = 60;
    const labelHeight = 30; // space reserved for tier labels at top

    // Compute column x-coordinates
    const tierX = {};
    for (let t = 0; t < NUM_TIERS; t++) {
        tierX[t] = padX + t * (width - 2 * padX) / (NUM_TIERS - 1);
    }

    // Group non-intervention, non-label nodes by tier
    const tierBuckets = {};
    for (let t = 0; t < NUM_TIERS; t++) tierBuckets[t] = [];
    const interventionNodes = [];

    cy.nodes().forEach(n => {
        const sc = n.data('styleClass');
        if (sc === 'groupLabel') return; // labels positioned separately
        if (sc === 'intervention') {
            interventionNodes.push(n);
            return;
        }
        const tier = NODE_TIERS[n.id()];
        if (tier !== undefined) {
            tierBuckets[tier].push(n.id());
        }
    });

    const positions = {};

    // Place mechanism/evidence nodes in their tier columns
    for (let t = 0; t < NUM_TIERS; t++) {
        const ids = tierBuckets[t];
        if (ids.length === 0) continue;

        const x = tierX[t];
        const usableH = height - 2 * padY - labelHeight;
        const startY = padY + labelHeight;

        ids.forEach((id, i) => {
            const y = ids.length > 1
                ? startY + i * usableH / (ids.length - 1)
                : startY + usableH / 2;
            positions[id] = { x, y };
        });
    }

    // Place intervention nodes — offset to the left of their primary target
    const interventionsByTarget = {};
    interventionNodes.forEach(n => {
        // Find the primary target (first outgoing edge target)
        const targets = n.outgoers('edge').targets();
        let targetId = null;
        if (targets.length > 0) {
            targetId = targets[0].id();
        }
        if (!interventionsByTarget[targetId]) {
            interventionsByTarget[targetId] = [];
        }
        interventionsByTarget[targetId].push(n.id());
    });

    Object.entries(interventionsByTarget).forEach(([targetId, txIds]) => {
        const targetPos = positions[targetId];
        if (!targetPos) {
            // Target not yet positioned — place interventions in a default spot
            txIds.forEach((txId, i) => {
                positions[txId] = { x: padX - 60, y: padY + labelHeight + i * 35 };
            });
            return;
        }
        // Place interventions to the left of target, staggered vertically
        const offsetX = -80;
        txIds.forEach((txId, i) => {
            const staggerY = (i - (txIds.length - 1) / 2) * 35;
            positions[txId] = {
                x: targetPos.x + offsetX - (i % 2) * 40,
                y: targetPos.y + staggerY,
            };
        });
    });

    // Place tier label nodes at the top of each column
    for (let t = 0; t < NUM_TIERS; t++) {
        positions[`_tier_${t}`] = { x: tierX[t], y: padY };
    }

    return positions;
}

function runTieredLayout(cy, container) {
    const w = container.offsetWidth || 900;
    const h = container.offsetHeight || 500;
    const positions = computeTieredPositions(cy, w, h);
    cy.layout({
        name: 'preset',
        positions: (node) => positions[node.id()] || undefined,
        fit: false,
        padding: 40,
        animate: false,
    }).run();
    cy.fit(cy.elements(), 40);
}

// ═══════════════════════════════════════════════════════════
// ELK LAYOUT (used for edit-mode preview only)
// ═══════════════════════════════════════════════════════════

function runElkLayout(cy) {
    try {
        const layout = cy.layout({
            name: 'elk',
            nodeDimensionsIncludeLabels: true,
            fit: true,
            padding: 30,
            animate: false,
            elk: {
                'algorithm': 'layered',
                'elk.direction': 'RIGHT',
                'elk.spacing.nodeNode': 20,
                'elk.spacing.edgeNode': 12,
                'elk.spacing.edgeEdge': 8,
                'elk.layered.spacing.nodeNodeBetweenLayers': 50,
                'elk.layered.spacing.edgeNodeBetweenLayers': 15,
                'elk.layered.edgeRouting': 'ORTHOGONAL',
                'elk.layered.cycleBreaking.strategy': 'GREEDY',
                'elk.layered.crossingMinimization.strategy': 'LAYER_SWEEP',
                'elk.layered.nodePlacement.strategy': 'NETWORK_SIMPLEX',
            }
        });
        layout.run();
    } catch (e) {
        console.warn('ELK layout failed, using grid fallback:', e);
        cy.layout({ name: 'grid', fit: true, padding: 30 }).run();
    }
}

// ═══════════════════════════════════════════════════════════
// CUSTOM WHEEL HANDLER (trackpad pan / shift+zoom)
// ═══════════════════════════════════════════════════════════

function attachWheelHandler(container, cy) {
    if (container._wheelHandler) {
        container.removeEventListener('wheel', container._wheelHandler);
    }

    const handler = (e) => {
        e.preventDefault();

        if (e.shiftKey) {
            // Shift + scroll = zoom toward cursor
            const zoomFactor = e.deltaY > 0 ? 0.9 : 1.1;
            const currentZoom = cy.zoom();
            const newZoom = Math.max(0.1, Math.min(10, currentZoom * zoomFactor));
            const rect = container.getBoundingClientRect();
            cy.zoom({
                level: newZoom,
                renderedPosition: {
                    x: e.clientX - rect.left,
                    y: e.clientY - rect.top
                }
            });
        } else {
            // Normal scroll = pan
            cy.panBy({ x: -e.deltaX, y: -e.deltaY });
        }
    };

    container.addEventListener('wheel', handler, { passive: false });
    container._wheelHandler = handler;
}

// ═══════════════════════════════════════════════════════════
// ZOOM CONTROLS
// ═══════════════════════════════════════════════════════════

function addZoomControls(container, cy) {
    const existing = container.querySelector('.panzoom-controls');
    if (existing) existing.remove();

    const controls = document.createElement('div');
    controls.className = 'panzoom-controls';
    controls.innerHTML = `
        <button class="panzoom-btn" title="Zoom in" data-action="zoomIn">+</button>
        <button class="panzoom-btn" title="Zoom out" data-action="zoomOut">&minus;</button>
        <button class="panzoom-btn" title="Fit to view" data-action="fit">&#x21BA;</button>
        <button class="panzoom-btn" title="Fullscreen" data-action="fullscreen">&#x26F6;</button>
        <button class="panzoom-btn panzoom-btn-toggle ${showInterventions ? 'active' : ''}" title="${showInterventions ? 'Hide interventions' : 'Show interventions'}" data-action="toggleTx">Tx</button>
    `;

    const center = () => ({ x: container.offsetWidth / 2, y: container.offsetHeight / 2 });

    controls.querySelector('[data-action="zoomIn"]').addEventListener('click', () => {
        cy.zoom({ level: cy.zoom() * 1.5, renderedPosition: center() });
    });
    controls.querySelector('[data-action="zoomOut"]').addEventListener('click', () => {
        cy.zoom({ level: cy.zoom() * 0.67, renderedPosition: center() });
    });
    controls.querySelector('[data-action="fit"]').addEventListener('click', () => {
        cy.fit(undefined, 30);
    });
    controls.querySelector('[data-action="fullscreen"]').addEventListener('click', () => {
        toggleFullscreen(container, cy);
    });
    controls.querySelector('[data-action="toggleTx"]').addEventListener('click', () => {
        toggleInterventions();
    });

    controls.addEventListener('mousedown', (e) => e.stopPropagation());
    controls.addEventListener('touchstart', (e) => e.stopPropagation());

    container.appendChild(controls);
}

// ═══════════════════════════════════════════════════════════
// INTERVENTION HIGHLIGHT SYSTEM (hover-to-highlight + click-to-pin)
// ═══════════════════════════════════════════════════════════

function applyInterventionDimming(cy) {
    cy.batch(() => {
        // Dim all non-intervention, non-group, non-label nodes
        cy.nodes().filter(n => n.data('styleClass') !== 'intervention' && n.data('styleClass') !== 'groupLabel' && !n.isParent()).addClass('tx-dimmed');
        // Dim all non-intervention edges
        cy.edges().filter(e => !e.data('isInterventionEdge')).addClass('tx-dimmed');
    });
}

function highlightIntervention(cy, nodeId) {
    cy.batch(() => {
        // Deep-dim everything first
        cy.elements().addClass('tx-deep-dimmed').removeClass('tx-dimmed tx-highlighted tx-target-highlighted');

        // Keep parent/group nodes and group labels somewhat visible
        cy.nodes(':parent').removeClass('tx-deep-dimmed').addClass('tx-dimmed');
        cy.nodes('[styleClass="groupLabel"]').removeClass('tx-deep-dimmed');

        // Highlight the hovered intervention node
        const node = cy.getElementById(nodeId);
        node.removeClass('tx-deep-dimmed').addClass('tx-highlighted');

        // Highlight its outgoing edges and target nodes
        const edges = node.outgoers('edge');
        edges.removeClass('tx-deep-dimmed').addClass('tx-highlighted');
        edges.targets().removeClass('tx-deep-dimmed').addClass('tx-target-highlighted');

        // Also highlight any pinned interventions
        pinnedInterventions.forEach(pinnedId => {
            const pNode = cy.getElementById(pinnedId);
            if (pNode.length) {
                pNode.removeClass('tx-deep-dimmed').addClass('tx-pinned tx-highlighted');
                const pEdges = pNode.outgoers('edge');
                pEdges.removeClass('tx-deep-dimmed').addClass('tx-highlighted');
                pEdges.targets().removeClass('tx-deep-dimmed').addClass('tx-target-highlighted');
            }
        });
    });
}

function restorePinnedState(cy) {
    cy.batch(() => {
        cy.elements().removeClass('tx-deep-dimmed tx-highlighted tx-target-highlighted tx-pinned');

        if (pinnedInterventions.size > 0) {
            // Deep-dim everything, then highlight pinned
            cy.elements().addClass('tx-deep-dimmed');
            cy.nodes(':parent').removeClass('tx-deep-dimmed').addClass('tx-dimmed');
            cy.nodes('[styleClass="groupLabel"]').removeClass('tx-deep-dimmed');

            pinnedInterventions.forEach(pinnedId => {
                const node = cy.getElementById(pinnedId);
                if (node.length) {
                    node.removeClass('tx-deep-dimmed').addClass('tx-pinned tx-highlighted');
                    const edges = node.outgoers('edge');
                    edges.removeClass('tx-deep-dimmed').addClass('tx-highlighted');
                    edges.targets().removeClass('tx-deep-dimmed').addClass('tx-target-highlighted');
                }
            });
        } else {
            // No pins — restore baseline dimming
            applyInterventionDimming(cy);
        }
    });
}

function attachInterventionHandlers(cy) {
    cy.on('mouseover', 'node[styleClass="intervention"]', (evt) => {
        highlightIntervention(cy, evt.target.id());
    });

    cy.on('mouseout', 'node[styleClass="intervention"]', () => {
        restorePinnedState(cy);
    });

    cy.on('tap', 'node[styleClass="intervention"]', (evt) => {
        const id = evt.target.id();
        if (pinnedInterventions.has(id)) {
            pinnedInterventions.delete(id);
        } else {
            pinnedInterventions.add(id);
        }
        restorePinnedState(cy);
    });
}

function toggleInterventions() {
    showInterventions = !showInterventions;
    if (!showInterventions) pinnedInterventions.clear();
    if (_fullscreenContainer) {
        // Only re-render the fullscreen graph (others are hidden behind it)
        const config = GRAPH_CONFIGS.find(c => c.cyContainerId === _fullscreenContainer.id);
        if (config) renderGraph(config);
    } else {
        renderAllGraphs();
    }
}

// ═══════════════════════════════════════════════════════════
// FULLSCREEN
// ═══════════════════════════════════════════════════════════

let _fullscreenContainer = null;

function toggleFullscreen(container, cy) {
    if (container.classList.contains('fullscreen')) {
        exitFullscreen(container, cy);
    } else {
        enterFullscreen(container, cy);
    }
}

function enterFullscreen(container, cy) {
    _fullscreenContainer = container;
    container._scrollY = window.scrollY;
    container.classList.add('fullscreen');

    const hint = document.createElement('div');
    hint.className = 'fullscreen-hint';
    hint.textContent = 'Press Esc to exit fullscreen';
    container.appendChild(hint);
    setTimeout(() => { hint.style.transition = 'opacity 1s'; hint.style.opacity = '0'; }, 3000);
    setTimeout(() => { hint.remove(); }, 4000);

    const fsBtn = container.querySelector('[data-action="fullscreen"]');
    if (fsBtn) { fsBtn.innerHTML = '&#x2716;'; fsBtn.title = 'Exit fullscreen'; }

    setTimeout(() => { cy.resize(); runTieredLayout(cy, container); }, 50);
}

function exitFullscreen(container, cy) {
    _fullscreenContainer = null;
    container.classList.remove('fullscreen');

    const hint = container.querySelector('.fullscreen-hint');
    if (hint) hint.remove();

    const fsBtn = container.querySelector('[data-action="fullscreen"]');
    if (fsBtn) { fsBtn.innerHTML = '&#x26F6;'; fsBtn.title = 'Fullscreen'; }

    setTimeout(() => {
        cy.resize();
        runTieredLayout(cy, container);
        if (container._scrollY !== undefined) window.scrollTo(0, container._scrollY);
    }, 50);
}

// Global Escape key handler
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && _fullscreenContainer) {
        const cy = cyInstances.get(_fullscreenContainer.id);
        if (cy) exitFullscreen(_fullscreenContainer, cy);
    }
});

// ═══════════════════════════════════════════════════════════
// RESIZE HANDLER
// ═══════════════════════════════════════════════════════════

let _resizeTimeout = null;
window.addEventListener('resize', () => {
    clearTimeout(_resizeTimeout);
    _resizeTimeout = setTimeout(() => {
        cyInstances.forEach((cy, containerId) => {
            const container = document.getElementById(containerId);
            if (container && (container.offsetParent !== null || container.classList.contains('fullscreen'))) {
                cy.resize();
                runTieredLayout(cy, container);
            }
        });
    }, 250);
});

// ═══════════════════════════════════════════════════════════
// RENDER
// ═══════════════════════════════════════════════════════════

function renderAllGraphs() {
    GRAPH_CONFIGS.forEach(config => {
        const container = document.getElementById(config.containerId);
        if (container && !container.classList.contains('edit-mode')) {
            renderGraph(config);
        }
    });
}

function renderGraph(config) {
    const cyContainer = document.getElementById(config.cyContainerId);
    if (!cyContainer) return;

    const wasFullscreen = cyContainer.classList.contains('fullscreen');
    destroyCyInstance(config.cyContainerId);

    // Only init if visible (hidden containers cause zero dimensions).
    // offsetParent is null for position:fixed (fullscreen) — handle that case.
    if (cyContainer.offsetParent !== null || wasFullscreen) {
        const cy = createCyInstance(config.cyContainerId, currentGraphData);
        // Restore fullscreen state after recreation
        if (wasFullscreen && cy) {
            _fullscreenContainer = cyContainer;
            const fsBtn = cyContainer.querySelector('[data-action="fullscreen"]');
            if (fsBtn) { fsBtn.innerHTML = '\u2716'; fsBtn.title = 'Exit fullscreen'; }
            setTimeout(() => { cy.resize(); runTieredLayout(cy, cyContainer); }, 50);
        }
    }
}

// ═══════════════════════════════════════════════════════════
// EXPORTS
// ═══════════════════════════════════════════════════════════

function escapeHtml(text) {
    if (!text) return '';
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

export function getGraphData() {
    return currentGraphData;
}

/**
 * Refresh Cytoscape instances after layout changes (e.g. tab switch).
 */
export function refreshPanZoom() {
    setTimeout(() => {
        GRAPH_CONFIGS.forEach(config => {
            const container = document.getElementById(config.cyContainerId);
            if (!container) return;

            if (container.offsetParent !== null || container.classList.contains('fullscreen')) {
                const cy = cyInstances.get(config.cyContainerId);
                if (cy) {
                    cy.resize();
                    runTieredLayout(cy, container);
                } else {
                    createCyInstance(config.cyContainerId, currentGraphData);
                }
            }
        });
    }, 100);
}
