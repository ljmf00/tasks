#!/usr/bin/env dub
/+ dub.sdl:
dependency "dyaml" version="~>0.8.4"
dependency "commonmark-d" version="~>1.0.8"
+/

module generate_all;

import std.format : format;
import std.ascii : newline, letters;
import std.string : strip, endsWith, leftJustify;
import std.array : split, join, array;
import std.range : chain;
import std.stdio : stdin, stderr, writeln;
import std.getopt : getopt, defaultGetoptPrinter;
import std.process : pipeProcess, nativeShell, wait;
import std.conv : to;
import core.stdc.stdlib : malloc, free;
import std.path : buildPath, stripExtension, baseName, dirName;
import std.datetime.date : DateTime;
import std.algorithm;
import std.file;

import dyaml;
import commonmarkd;

// shared

static immutable IO_FD_CHUNK_SIZE = 4096; // 4kb
ubyte[] ioChunkBuffer = void;
string tmpDir = void;

static this() {
    // preallocate IO chunk buffer
    auto ptr = cast(ubyte*)malloc(IO_FD_CHUNK_SIZE);
    if(!ptr) {
        import core.stdc.stdio : stderr, fprintf;
        import core.stdc.string : strerror;
        import core.stdc.errno : errno;
        stderr.fprintf("%s", errno.strerror);
        assert(0);
    }
    ioChunkBuffer = ptr[0 .. IO_FD_CHUNK_SIZE];

    // handle temporary directory
    do {
        import std.random : randomSample;
        import std.utf : byCodeUnit;
        auto randPayload = letters.byCodeUnit.randomSample(20).to!string;
        tmpDir = tempDir.buildPath(randPayload);
    } while (exists(tmpDir));
    mkdirRecurse(tmpDir);
}

static ~this() {
    free(ioChunkBuffer.ptr);
    remove(tmpDir);
}

auto genMinifiedText(string input)
{ return input.splitter(newline).map!strip.join.strip; }

static immutable string HTML_TEMPLATE = `
<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <title>%s</title>
    <style>
    body{
        color:white;
        background-color:black;
        text-align:center;
    }
    a{
        color:white;
    }
    </style>
</head>
<body><pre>%s</pre>
</body>
</html>
`.genMinifiedText;

auto genHeader(string input)
{ return input.splitter(newline).map!strip.join(" | ").strip(" | "); }

static immutable string HTML_DEFAULT_HEADER = `
<a href="../index.html">home</a>
`.genHeader;
static immutable string HTML_DEFAULT_FOOTER = `
`.genHeader;

auto genHTMLFilesHeader(string status)()
{
    return format!(`
        <a href="../index.html">home</a>
        <a href="../files/%s/">raw</a>
    `.genHeader)(status);
}

static immutable string HTML_HOME_HEADER = `
<a href="resolved/index.html">resolved</a>
<a href="templates/index.html">templates</a>
<a href="files/recurring/">recurring</a>
<a href="files/pending/">pending</a>
<a href="paused/index.html">paused</a>
<a href="files/delegated/">delegated</a>
<a href="files/deferred/">deferred</a>
<a href="active/index.html">active</a>
<a href="unorganised/index.html">unorganised</a>
<a href="all/index.html">all</a>
`.genHeader;

static immutable string HTML_HOME_FOOTER = `
<a href="projects/index.html">projects</a>
<a href="tags/index.html">tags</a>
`.genHeader;

auto fakeTTYShellPipe(string[] command)
{
    static immutable COLUMNS = 180;
    static immutable ROWS = 100_000;
    immutable nshell = nativeShell();
    assert(nshell.endsWith("/sh"));

    return pipeProcess(
        ["script", "-qefc",
            format!"%s -c 'stty cols %d; stty rows %d; %(%s %)'"(
                nshell,
                COLUMNS,
                ROWS,
                command
            )
        ]);
}

DateTime tryToDateTimeFromString(string input)
{
    import core.time : TimeException;
    try { return DateTime.fromSimpleString(input); } catch(TimeException) {}
    try { return DateTime.fromISOString(input); } catch(TimeException) {}
    return DateTime.fromISOExtString(input);
}

static immutable string[] TASK_TYPES = [
    "template",
    "resolved",
    "recurring",
    "pending",
    "paused",
    "delegated",
    "deferred",
    "active"
];

string toColor(Task.Priority p)
{
    final switch(p) with(Task.Priority)
    {
        case P3: return "8a8a8a";
        case P2: return "c0c0c0";
        case P1: return "d75f00";
        case P0: return "d70000";
    }
}

struct Task
{
    enum Priority {
        P0,
        P1,
        P2,
        P3,
    }

    string uuid;
    string status;
    string summary;
    string[] tags;
    string notes;
    string project;
    Priority priority;
    string delegatedto;
    string created;
    DateTime createdDate;
    string resolved;
    DateTime resolvedDate;
    string due;
    DateTime dueDate;

    ref Task fromNode(Node root) return
    {
        if("summary" in root) summary = root["summary"].as!string;
        if("notes" in root) notes = root["notes"].as!string;
        if("tags" in root) tags = root["tags"].sequence!string.array;
        if("project" in root) project = root["project"].as!string;
        if("delegatedto" in root) delegatedto = root["delegatedto"].as!string;
        if("priority" in root) priority = root["priority"].as!string.to!Priority;
        if("created" in root) {
            created = root["created"].as!string;
            createdDate = tryToDateTimeFromString(created.split(".")[0]);
        }
        if("resolved" in root) {
            resolved = root["resolved"].as!string;
            resolvedDate = tryToDateTimeFromString(created.split(".")[0]);
        }
        if("due" in root) {
            due = root["due"].as!string;
            dueDate = tryToDateTimeFromString(created.split(".")[0]);
        }

        return this;
    }
}

auto fakeTTYShellOutput(string[] command)
{
    auto pipe = fakeTTYShellPipe(command);
    pipe.stdin.close();

    ubyte[] ret = pipe.stdout.byChunk(ioChunkBuffer).joiner.array;
    pipe.stderr.flush();
    wait(pipe.pid);

    return ret;
}

auto buffer2HTML(ubyte[] input)
{
    auto cwd = getcwd();
    scope(exit) chdir(cwd);

    chdir(tmpDir);
    auto pipe = pipeProcess(["aha", "-n"]);
    // write to stdin
    pipe.stdin.rawWrite(input);
    pipe.stdin.flush(); pipe.stdin.close();

    // fetch result from stdout
    ubyte[] ret = pipe.stdout.byChunk(ioChunkBuffer).joiner.array;
    pipe.stderr.flush();
    wait(pipe.pid);
    return ret;
}

auto shellOutput2HTML(string[] command)
{
    return buffer2HTML(fakeTTYShellOutput(command));
}

auto genHtmlTemplate(string title, string content)
{
    return format!HTML_TEMPLATE
        (title ? chain("Tasks :: ", title).array : "Tasks", content);
}

void genDSTaskHTML(
        string subdir, string subcommand,
        string title = null,
        string header = HTML_DEFAULT_HEADER,
        string footer = HTML_DEFAULT_FOOTER
    )
{
    mkdirRecurse(subdir);
    auto html = genHtmlTemplate(title,
            format!"%s\n\n%s\n%s"(
                header,
                cast(string)shellOutput2HTML(["dstask", subcommand]),
                footer)
        );
    write(buildPath(subdir, "index.html"), html);
}

int main(string[] args)
{
    bool template_;
    string title;

    auto opt = getopt(
        args,
        "T|template", "Print the HTML template with a given content from stdin", &template_,
        "t|title", "Custom title", &title);

    if (opt.helpWanted)
    {
        defaultGetoptPrinter("Some information about the program.",
            opt.options);
    }

    if (template_)
    {
        writeln(genHtmlTemplate(title, cast(string)buffer2HTML(stdin.byChunk(ioChunkBuffer).joiner.array)));
        return 0;
    }

    if (title)
    {
        stderr.writeln("Option --title requires --template");
        return 1;
    }

    string workspaceDir = getcwd();
    string outputDir = buildPath(workspaceDir, "public");
    Task[string] tasks;

    mkdirRecurse(buildPath(outputDir, "files", "all"));

    // home (open tasks)
    genDSTaskHTML(
        outputDir, "show-open", null,
        HTML_HOME_HEADER, HTML_HOME_FOOTER);
    // projects
    genDSTaskHTML(
        buildPath(outputDir, "projects"),
        "show-projects", "Projects");
    // tags
    genDSTaskHTML(
        buildPath(outputDir, "tags"),
        "show-tags", "Tags");
    // unorganised
    genDSTaskHTML(
        buildPath(outputDir, "unorganised"),
        "show-unorganised", "Unorganised");
    // templates
    genDSTaskHTML(
        buildPath(outputDir, "templates"),
        "show-templates", "Templates",
        genHTMLFilesHeader!"template");
    // resolved
    genDSTaskHTML(
        buildPath(outputDir, "resolved"),
        "show-resolved", "Resolved",
        genHTMLFilesHeader!"resolved");
    // paused
    genDSTaskHTML(
        buildPath(outputDir, "paused"),
        "show-paused", "Paused",
        genHTMLFilesHeader!"paused");
    // active
    genDSTaskHTML(
        buildPath(outputDir, "active"),
        "show-active", "Active",
        genHTMLFilesHeader!"active");

    size_t maxSummarySize = 0;
    bool striped;
    auto getStriped = () { striped = !striped; return striped; };

    // loop tasks
    TASK_TYPES
        .map!(t => buildPath(workspaceDir, t))
        .filter!(d => d.exists)
        .map!(d =>
            d.dirEntries("*.{yml,yaml}", SpanMode.depth)
                .filter!(f => f.isFile)
        ).joiner
        .each!((file) {
            string name = file.name;
            string base = baseName(name);
            string dir = dirName(name);
            string uuid = base.stripExtension;
            string status = baseName(dir);
            string outputStatusDir = buildPath(outputDir, "files", status);
            mkdirRecurse(outputStatusDir);
            copy(file.name, buildPath(outputStatusDir, base));
            copy(file.name, buildPath(outputDir, "files", "all", base));

            Node root = Loader.fromFile(name).load();
            tasks[uuid] = Task(uuid, status).fromNode(root);
            maxSummarySize = max(maxSummarySize, tasks[uuid].summary.length);
        });

    auto sorted = tasks.values.dup
        .multiSort!("a.priority < b.priority", "a.createdDate > b.createdDate");

    auto allHTML = sorted.map!((task) =>
        format!`<span style="background-color:#%1$s;"><a style="text-decoration:none;color:#%2$s;" href="../files/all/%3$s.yml">%3$s  %4$s</a></span>`(
            getStriped() ? "0a0a0a" : "000000",
            task.priority.toColor(),
            task.uuid,
            leftJustify(task.summary.strip, maxSummarySize, ' ')
        )).join(newline) ~ format!"\n\n%d tasks."(tasks.length);


    mkdirRecurse(buildPath(outputDir, "all"));
    auto html = genHtmlTemplate("All",
            format!"%s\n\n%s\n%s"(
                genHTMLFilesHeader!"all",
                allHTML,
                HTML_DEFAULT_FOOTER)
        );
    write(buildPath(outputDir, "all", "index.html"), html);

    /* convertMarkdownToHTML(tasks[uuid].notes).writeln; */
    /* writeln(cast(string)shellOutput2HTML(["dstask"])); */

    return 0;
}
