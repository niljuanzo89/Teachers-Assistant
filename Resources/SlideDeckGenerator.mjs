import fs from "node:fs/promises";

const [inputPath, destination] = process.argv.slice(2);
if (!inputPath || !destination) throw new Error("Expected an input JSON path and destination PPTX path.");
const artifactToolEntry = process.env.LESSONPLANNER_ARTIFACT_TOOL_ENTRY;
if (!artifactToolEntry) throw new Error("Presentation runtime path was not provided.");

const { Presentation, PresentationFile } = await import(artifactToolEntry);
const lesson = JSON.parse(await fs.readFile(inputPath, "utf8"));
const deck = Presentation.create({ slideSize: { width: 1280, height: 720 } });

const ink = "#202020";
const muted = "#666666";
const teal = "#0088B0";
const rose = "#D6006C";
const paper = "#F4F3F2";
const safe = (value, fallback) => compact(value) || fallback;
const compact = (value) => String(value || "").replace(/\s+/g, " ").trim();
const limit = (value, max) => {
  const clean = compact(value);
  return clean.length > max ? `${clean.slice(0, max - 1).trim()}…` : clean;
};
const stepTitle = (step) => limit(step?.title || step?.notes || "", 140);
const stepText = (steps) => {
  const lines = steps.map(stepTitle).filter(Boolean);
  return lines.map((title) => `• ${title}`).join("\n") || "• Add teacher-reviewed instructional steps in LessonPlanner.";
};
const chunk = (items, size) => {
  const chunks = [];
  for (let index = 0; index < items.length; index += size) chunks.push(items.slice(index, index + size));
  return chunks;
};

function textSize(value, large, medium, small, tiny) {
  const length = compact(value).length;
  if (length > 260) return tiny;
  if (length > 175) return small;
  if (length > 110) return medium;
  return large;
}

function titleSize(value) {
  const length = compact(value).length;
  if (length > 95) return 31;
  if (length > 75) return 36;
  if (length > 55) return 44;
  return 54;
}

function bulletSize(steps) {
  const totalLength = steps.map(stepTitle).join(" ").length;
  if (steps.length >= 5 || totalLength > 420) return 22;
  if (steps.length >= 4 || totalLength > 300) return 24;
  return 28;
}

function text(slide, value, left, top, width, height, size, options = {}) {
  const box = slide.shapes.add({
    geometry: "textbox",
    position: { left, top, width, height },
    fill: "none",
    line: { style: "solid", fill: "none", width: 0 },
  });
  box.text = value;
  box.text.style = {
    fontSize: size,
    color: options.color || ink,
    bold: options.bold || false,
    alignment: options.alignment || "left",
    fontFace: options.fontFace || "Aptos",
  };
}

function base(title, number, accent = teal) {
  const slide = deck.slides.add();
  slide.background.fill = paper;
  text(slide, title, 72, 66, 1136, 68, 38, { bold: true, fontFace: "Georgia" });
  slide.shapes.add({ geometry: "rect", position: { left: 72, top: 155, width: 1136, height: 5 }, fill: accent, line: { style: "solid", fill: accent, width: 0 } });
  text(slide, `${limit(safe(lesson.title, "Lesson"), 95)}  •  ${number}`, 72, 674, 1136, 18, 13, { color: muted });
  return slide;
}

let slide = deck.slides.add();
slide.background.fill = paper;
const lessonTitle = safe(lesson.title, "Lesson");
const lessonObjective = safe(lesson.objective, "Explore the teacher-reviewed learning objective.");
text(slide, lessonTitle, 72, 112, 1030, 166, titleSize(lessonTitle), { bold: true, fontFace: "Georgia" });
text(slide, `${safe(lesson.subject, "Lesson")}  •  ${safe(lesson.gradeOrAgeRange, "Grade level not specified")}`, 76, 306, 850, 34, 24, { color: muted });
slide.shapes.add({ geometry: "rect", position: { left: 72, top: 372, width: 550, height: 7 }, fill: teal, line: { style: "solid", fill: teal, width: 0 } });
text(slide, "Today we will", 76, 414, 300, 30, 22, { color: muted, bold: true });
text(slide, lessonObjective, 76, 456, 970, 132, textSize(lessonObjective, 32, 28, 24, 21), { bold: true });
text(slide, `${limit(lessonTitle, 95)}  •  1`, 72, 674, 1136, 18, 13, { color: muted });

slide = base("Learning goal", 2);
text(slide, "I can…", 110, 214, 250, 34, 25, { color: teal, bold: true });
text(slide, lessonObjective, 110, 270, 1000, 135, textSize(lessonObjective, 38, 32, 27, 23), { bold: true });
text(slide, "Success looks like explaining your strategy and showing your work clearly.", 110, 420, 960, 42, 24, { color: muted });

const steps = Array.isArray(lesson.instructionalSequence) ? lesson.instructionalSequence : [];
let slideNumber = 3;
slide = base("Warm up and connect", slideNumber);
const warmUpSteps = steps.slice(0, 3);
text(slide, stepText(warmUpSteps), 100, 210, 1040, 290, bulletSize(warmUpSteps));
text(slide, "Talk with a partner: What do you already know that can help?", 100, 540, 970, 38, 24, { color: teal, bold: true });

slideNumber += 1;
slide = base("Build understanding together", slideNumber);
const buildSteps = steps.slice(3, 6);
text(slide, stepText(buildSteps), 100, 210, 1040, 310, bulletSize(buildSteps));
text(slide, "Use diagrams, models, and clear explanations to make your reasoning visible.", 100, 550, 1020, 38, 24, { color: muted });

const practiceGroups = chunk(steps.slice(6), 4);
const practiceSlides = practiceGroups.length ? practiceGroups : [[]];
for (const [index, group] of practiceSlides.entries()) {
  slideNumber += 1;
  slide = base(index === 0 ? "Practice and explain" : "Continue practice", slideNumber);
  text(slide, stepText(group), 100, 210, 1040, 190, bulletSize(group));
  text(slide, "Show your work", 100, 430, 350, 36, 30, { color: rose, bold: true });
  text(slide, "1. Choose a strategy.\n2. Represent it with a model or equation.\n3. Explain why it works.", 100, 485, 900, 105, 27);
}

slideNumber += 1;
slide = base("Choose the support you need", slideNumber, rose);
const differentiation = safe(lesson.differentiationSummary, "Use a teacher-selected support, challenge, or small-group activity.");
text(slide, differentiation, 100, 210, 1040, 260, textSize(differentiation, 28, 25, 22, 20));
text(slide, "Ask for the tool or example that will help you take the next step.", 100, 530, 1020, 38, 24, { color: rose, bold: true });

slideNumber += 1;
slide = base("Exit ticket", slideNumber);
const exitPrompt = lesson.objective ? `${compact(lesson.objective)} Show your model and explain your reasoning.` : "Show what you learned today.";
text(slide, exitPrompt, 100, 215, 1040, 125, textSize(exitPrompt, 36, 31, 27, 23), { bold: true });
const assessment = safe(lesson.assessmentSummary, "Be ready to explain your model, equation, or reasoning.");
text(slide, assessment, 100, 380, 900, 80, textSize(assessment, 26, 23, 20, 18), { color: muted });
text(slide, "Before you leave: What strategy helped you most?", 100, 510, 920, 42, 28, { color: teal, bold: true });

for (const current of deck.slides.items) {
  current.speakerNotes.textFrame.setText(`[Sources]\n- Local approved LessonPlanner record, ${safe(lesson.title, "Lesson")}.\n[/Sources]`);
  current.speakerNotes.setVisible(true);
}

const pptx = await PresentationFile.exportPptx(deck);
await pptx.save(destination);
