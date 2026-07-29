# LessonPlanner Glossary

Plain-language definitions for the terms used while planning and building LessonPlanner.

## A

**AI (artificial intelligence)**  
Software that can analyze or generate language, images, or other content. In this project, AI may help turn reviewed source text into a lesson draft, but it is optional and never makes the final decision.

**AI provider**  
The company or system that supplies an AI model, such as OpenAI/Codex, Anthropic/Claude, or a locally run model. The long-term app should be able to work with more than one provider rather than depending on only one.

**API (application programming interface)**  
A structured way for one piece of software to ask another piece of software to do something. An API is usually invisible to the teacher using the app.

**App data**  
The information LessonPlanner saves for itself, such as lesson records, schedules, checklist items, and output history. It is stored separately from the project code.

**Approval state**  
The label that tells the app whether a lesson is still a draft, has been reviewed, or is ready to generate final materials. Only approved lessons can create outputs.

## B

**Bridge**  
A temporary connector between LessonPlanner and another tool. The current personal PowerPoint bridge connects the app to a presentation tool already installed on the owner’s Mac. It is useful for testing but is not the planned customer version.

**Build**  
The process of turning the app’s source code into a runnable Mac application. Xcode performs the build when you press Run.

## C

**Canonical lesson record**  
The one complete, approved lesson entry that serves as the source of truth for every output. Instead of separately writing a lesson plan, slide deck, and differentiation guide, the app creates all three from this one record.

**Codex CLI**  
The command-line version of Codex. In the personal build, LessonPlanner can optionally use it to request an AI lesson draft. “CLI” means command-line interface.

**Configuration**  
The app’s saved choices, such as the workspace name and the folders selected for sources, templates, and generated outputs.

## D

**Daily planner**  
The part of LessonPlanner intended to show the day’s schedule and checklist. The long-term design includes a small, glanceable view and a larger full planning workspace.

**Developer runtime**  
Software installed for development work rather than for ordinary customers. The current personal PowerPoint export uses one of these, which is why it must be replaced before selling the app.

**Differentiation**  
Planned adjustments, supports, extensions, small-group activities, or alternative materials that help different learners access the same lesson.

**Draft**  
A lesson record that is still being created or edited. A draft cannot generate classroom outputs until the teacher approves it.

## E

**Editable output**  
A generated file that a teacher can still change afterward. For example, the app’s PowerPoint deck can be opened and edited in PowerPoint or uploaded to Google Slides.

**Extraction**  
The process of taking useful text or labeled information out of a source document. Extraction may be direct (the PDF already contains text), rule-based, or AI-assisted.

## G

**Generative AI**  
AI that writes or creates new content, such as a lesson draft. It can be useful, but it can also make mistakes or add unsupported details, which is why LessonPlanner requires teacher review.

**Google Slides round-trip**  
The practical test of exporting a PowerPoint file, uploading it to Google Drive, opening it in Google Slides, and checking whether the layout remains usable and editable.

## H

**HTML**  
A common format used to structure a web page. LessonPlanner currently creates lesson-plan and differentiation-guide outputs as HTML files because they are portable, printable, and easy to open in a browser.

## I

**Ingestion**  
The first stage of bringing source files into the app so they can be read, reviewed, and used for planning.

**IP (intellectual property)**  
Creative work that may have legal ownership, such as source code, written material, designs, templates, and curriculum. This project deliberately keeps its general product code separate from school-specific resources.

## L

**Local-first**  
An approach where the app works primarily with files and data on the teacher’s own computer. It reduces dependence on a remote service and gives the teacher more control over files and privacy.

## M

**Mac app / native app**  
An application built to run directly on macOS rather than inside a web browser. LessonPlanner is a native Mac app.

**Model**  
The underlying AI system that produces an answer or draft. Claude, Codex, and Llama are examples of model families.

**MCP (Model Context Protocol)**  
A technical standard that lets an AI system connect to approved tools or information sources in a structured way. It is a development-workflow concept, not a requirement for the LessonPlanner app itself.

## O

**OCR (optical character recognition)**  
Technology that reads printed words from an image or scan and turns them into editable text. It is helpful for scanned PDFs but may make mistakes, especially with handwriting, diagrams, and complex math notation.

**Output**  
A document or file created by the app from an approved lesson. The intended core outputs are a lesson plan, slide deck, and differentiation guide with printable resources.

**Output history**  
A local list of files LessonPlanner has created, including when they were made and which lesson created them.

## P

**PDF (portable document format)**  
A common document format. Some PDFs contain selectable text; others are scans that are essentially pictures of pages and may need OCR.

**Phase**  
A planned stage of development. The project uses phases to keep the work manageable: define the architecture, build the local foundation, improve quality, refine optional AI, then prepare a sellable version.

**PowerPoint / PPTX**  
Microsoft PowerPoint’s editable presentation-file format. LessonPlanner uses PPTX as its first slide-deck format because it can also be uploaded to Google Slides.

**Provider-neutral**  
Designed so the app is not permanently tied to one AI company or model. A provider-neutral sellable version could support multiple AI choices—or no AI at all.

## R

**Renderer**  
The part of the app that turns structured lesson information into a finished file or layout. For example, an HTML renderer creates the lesson-plan webpage; a slide renderer creates a PowerPoint deck.

**Repository**  
The project’s organized collection of source code, documentation, tests, and supporting files. In ordinary conversation, this may simply be called the project folder.

**Reviewed source**  
Source text that a teacher has inspected and corrected after import. LessonPlanner treats this as safer input than raw PDF extraction.

## S

**Schema**  
The agreed-upon shape of structured information. For a lesson, it defines fields such as title, objective, materials, instructional steps, assessment, and differentiation.

**Source of truth**  
The one place considered authoritative when information appears in several places. In LessonPlanner, the approved lesson record is the source of truth for generated materials.

**Source provenance**  
A record of where lesson information came from, such as the name or location of an imported document. This helps the teacher trace an output back to its source.

**Structured data**  
Information stored in named fields rather than as one large block of text. Structured lesson data lets the app reliably place the right information in a lesson plan, deck, or guide.

**Swift / SwiftUI**  
Apple’s programming language and user-interface framework used to build the native Mac version of LessonPlanner.

## T

**Template**  
A reusable visual or document layout. A future version of LessonPlanner will allow teacher-owned templates—such as an HTML slide layout—to be filled with the approved lesson’s information.

**Test fixture**  
A safe sample file or sample data used to check whether an app works correctly. This project should use only non-sensitive, permitted examples as test fixtures.

## W

**Workspace**  
The teacher’s chosen working area in LessonPlanner, including its source folders, output folder, and planning records.

**Xcode**  
Apple’s development program for building and running Mac apps. The current LessonPlanner project is opened and run from Xcode during development.

