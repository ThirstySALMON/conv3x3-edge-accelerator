# docs/

    report/     what you write in
    figures/    what goes into the report
    notes/      reference only, not submitted

## Two PDFs get submitted

| file | from | length |
|---|---|---|
| `SSCS2026_Report.pdf` | `report/REPORT_SKELETON.md` | 25-35 pages |
| `SSCS2026_Slides.pdf` | `report/SLIDES_OUTLINE.md` | 11 slides |

Plus the source zip: `git archive --format=zip -o conv3x3_submission.zip v1.0-submission`
(the notes below are export-ignored, so they stay out of it).

## report/

    REPORT_SKELETON.md    write here - headings in the announcement's order, figure and
                          table numbers pre-assigned
    REPORT_OUTLINE.md     for each section: what to say, with the numbers, and which
                          figure belongs in it. READ THE CORRECTIONS BANNER FIRST
    SLIDES_OUTLINE.md     11 slides, same idea
    BLOCK_DIAGRAM_NOTES.md   the three diagrams to draw, and exactly what changed

## figures/

    waveforms/            10 PNGs, referenced as Figure 4.2, 6.1, 6.2, 11.1-11.6
    edge_demo_*.png       input next to the RTL output, three kernels - Figure 18.1

Diagrams still to draw (see BLOCK_DIAGRAM_NOTES.md): block diagram (Figure 2.1),
datapath (Figure 3.1), FSM state diagram (Figure 4.1).

## Where the numbers come from

    fpga/reports/RESULTS.md       every headline number, and the final-run confirmation
    docs/notes/POWER_METHODOLOGY.md   power method, the organiser's five items, SAIF interval
    docs/notes/DESIGN_ITERATIONS.md   what changed and why, including the attempt that failed
    fpga/reports/*.rpt            the raw Vivado reports

If a number in the outline disagrees with RESULTS.md, RESULTS.md wins.

## Order to work in

1. Draw the three diagrams (about an hour) - sections 2, 3 and 4 are blocked on them
2. Write sections 12, 13, 14, 16 first: the numbers are all measured, it is transcription
3. Then 1-11 and 15, 17-19, which need prose
4. Abstract last
5. Slides from the report, not from scratch
