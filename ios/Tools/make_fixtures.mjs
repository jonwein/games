// Runs the matching logic in ../../index.html over sample results and writes what it decides to
// DailyGamesTests/Fixtures/parity.json. ParityTests checks the Swift port gives the same answers, so a change
// to the web version's matching shows up as a failing test until the app catches up.
//
// Usage: node ios/Tools/make_fixtures.mjs

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(here, "../../index.html"), "utf8");
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];

// Just enough of a browser for the page script to load. Every DOM lookup returns an inert object.
const inert = new Proxy(function () {}, {
  get(_, prop) {
    if (prop === Symbol.iterator) return function* () {};
    if (prop === Symbol.toPrimitive) return () => "";
    if (prop === "then") return undefined;
    return inert;
  },
  set: () => true,
  apply: () => inert,
});
const storage = () => {
  const m = new Map();
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), removeItem: (k) => m.delete(k) };
};

const page = new Function(
  "document", "window", "navigator", "localStorage", "sessionStorage",
  script + `
  return {
    matcher, headLine, findLink, titleOf, guessGame, looksLikeResult, stripLinks, sharedTime, inMessage, nameFromUrl, normalizeUrl, mentioned, handleText, today,
    DEFAULT_GAMES,
    reset(g, s, opened) { games = g; state = s; lastOpened = opened; },
    hook(h) { add = h.add; addNew = h.addNew; pickGame = h.pickGame; toast = h.toast; },
  };`,
)(inert, inert, {}, storage(), storage());

const clone = (x) => JSON.parse(JSON.stringify(x));
const DEFAULTS = clone(page.DEFAULT_GAMES);

// Sample results, in the shapes games share them. They don't need to be word-perfect: what matters is that
// both versions read them the same way.
const TEXTS = {
  wordle: "Wordle 1,621 4/6\n\n⬛🟨⬛⬛⬛\n⬛⬛🟩🟨⬛\n🟩🟩🟩⬛⬛\n🟩🟩🟩🟩🟩",
  wordleCRLF: "Wordle 1,621 3/6\r\n\r\n🟩🟩🟩🟩🟩",
  connections: "Connections\nPuzzle #532\n🟨🟨🟨🟨\n🟩🟩🟩🟩\n🟦🟦🟦🟦\n🟪🟪🟪🟪",
  strands: "Strands #262\n“Hit the road”\n🔵🔵🟡🔵\n🔵🔵",
  mini: "I solved the 11/27/2026 New York Times Mini Crossword in 0:42!\nhttps://www.nytimes.com/badges/games/mini.html?d=2026-11-27&t=42&c=abc&smid=url-share",
  miniShort: "Mini 11/27 0:42 ⭐️",
  crossword: "I solved the Friday 11/27/2026 New York Times Daily Crossword in 12:34!\nhttps://www.nytimes.com/badges/games/crossword.html?d=2026-11-27&t=754&smid=url-share",
  spotle: "Spotle #800🎧\n\n⬜⬜⬜🟩\n\nspotle.io",
  spotleIo: "Spotle.io #800 ⬜🟩",
  spotle801: "Spotle #801🎧\n\n⬜🟩\n\nspotle.io",
  dailyTens: "DailyTens #120 🔟 7/10\nhttps://dailytens.com",
  songless: "Songless #312\n🟥🟥🟩⬜⬜⬜\nhttps://lessgames.com/songless/312",
  songlessLinkOnly: "🎵 #312\n🟥🟥🟩⬜⬜⬜\nhttps://lessgames.com/songless/312",
  perceptle: "Perceptle #42 - A (87)\nhttps://perceptle.com",
  krillion: "Krillion #95 🦐 4/6\nkrillion.io",
  bandle: "Bandle #500 3/6\n⬛🟥🟩⬜⬜⬜\n#Bandle #Heardle #Wordle\nhttps://bandle.app/",
  worldle: "#Worldle #800 (27.11.2026) 3/6 (100%)\n🟩🟩🟩🟩🟨⬅️\n🟩🟩🟩🟩🟩🎉\n\nhttps://worldle.teuteuf.fr",
  quordle: "Daily Quordle 800\n4️⃣5️⃣\n6️⃣7️⃣\nm-w.com/games/quordle/\n⬜🟨⬜⬜🟩",
  octordle: "Daily Octordle #900\n8️⃣4️⃣\n🕚🔟\nScore: 61",
  waffle: "#waffle800 4/5\n\n🟩🟩🟩🟩🟩\n🟩⭐️🟩⭐️🟩\n\n🔥 streak: 3\nwafflegame.net",
  grid: "Immaculate Grid 300 8/9:\nRarity: 432\n⬜🟩🟩\n🟩🟩🟩\n🟩🟩🟩\nPlay at:\nhttps://www.immaculategrid.com/grid-300",
  contexto: "I played contexto.me #500 and got it in 32 guesses.\n\n🟩 3\n🟨 8\n🟥 21",
  timeguessr: "TimeGuessr #500 39,450/50,000\n🌎🟩🟩⬛ 📅🟩🟩🟨\n🌎🟩⬛⬛ 📅🟩🟩🟩\nhttps://timeguessr.com",
  costcodle: "Costcodle #300 3/6\n⬆️🟥\n⬇️🟨\n✅\nhttps://costcodle.com",
  framed: "Framed #900\n🎥 🟥 🟥 🟩 ⬛ ⬛ ⬛\n\nhttps://framed.wtf",
  travle: "#travle #600 +2\n🟩🟩🟧✅\nhttps://travle.earth",
  globle: "🌎 Nov 27, 2026 🌍\n🔥 3 | Avg. Guesses: 7.5\n🟧🟥🟩 = 3\n\nhttps://globle-game.com\n#globle",
  pips: "Pips #100 Hard\n🟪 0:45",
  zip: "Zip #120 | 0:23 🏁\nWith no backtracks 🟢\nlnkd.in/zip.",
  queens: "Queens #300\n0:45 👑\nlnkd.in/queens.",
  chainle: "Chainle #12 🔗 3 links\nhttps://chainle.io",
  tradle: "#Tradle #900 2/6\n🟩🟩🟩🟩🟨\n🟩🟩🟩🟩🟩\nPlay Today's Game: https://oec.world/en/tradle",
  nerdle: "nerdlegame 900 3/6\n\n🟪🟩⬛🟪⬛🟩🟪⬛\n🟩🟩🟩🟩🟩🟩🟩🟩",
  heardle: "#Heardle #500\n\n🔉🟥⬜⬜⬜⬜⬜\n\nhttps://www.spotify.com/heardle?x=1",
  flagle: "I got today's Flagle in 2! 🇫🇷",
  filler: "Puzzle #12 solved! 🎉",
  todays: "Today's Dordle 3&5/7\n🟩🟩🟩🟩🟩 🟩🟩🟩🟩🟩",
  dated: "Nov 27 Bracket City 🏙️\nRank: Tourist\n❌ wrong guesses: 2",
  wwwLink: "Spellcheck 42\n✅✅❌\nwww.spellcheck.com/today",
  longTitle: "My Very Long Puzzle Name Here 3/6 🟩",
  accented: "Pokédoku 120 9/9\n🟩🟩🟩",
  unicodeSpace: "Daily Tens #121 ✅",
  plainUrl: "https://example.com/whatever",
  maptap: "www.maptap.gg November 27\n93🏆 67🙂 87🎓 88🎉 91👑\nFinal score: 871",
  miniShared: "https://www.nytimes.com/shared/v2/mini-xwd.html?d=2026-11-27&t=275&c=abc&smid=na-share",
  miniSharedSpaced: "  https://www.nytimes.com/shared/v2/mini-xwd.html?d=2026-11-27&t=5\n",
  crosswordShared: "https://nytimes.com/shared/v2/daily-xwd.html?t=3725&d=2026-11-27",
  sharedNoTime: "https://www.nytimes.com/shared/v2/mini-xwd.html?d=2026-11-27&t=",
  sharedNotNyt: "https://example.com/x?t=275",
  words: "hello world",
  empty: "",
  blank: "   \n  ",
};

const outcome = () => {
  let out = null;
  page.hook({
    add: (g, text) => { out = { kind: "add", game: g.id }; },
    addNew: (entry, text, guess = entry) => { out = { kind: "addNew", entry: clone(entry), guess: clone(guess) }; },
    pickGame: (text, guess, suggested, newFirst) => {
      out = { kind: "pick", guess: guess ? clone(guess) : null, suggested: suggested.map((g) => g.id), newFirst };
    },
    toast: (message) => { out = { kind: "toast", message }; },
  });
  return () => out;
};

function run({ games = DEFAULTS, results = {}, stale = [], lastOpened = null, text }) {
  page.reset(clone(games), { date: page.today(), results: clone(results), stale: clone(stale) }, lastOpened);
  const result = outcome();
  page.handleText(text);
  return result();
}

// How a result reads in the message, for a game with an alias, one with two words, and one results don't name.
const MESSAGE_GAMES = [
  ...DEFAULTS.filter((g) => g.id === "nytmini" || g.id === "dailytens"),
  { id: "gmaptap", name: "Maptap", url: "https://maptap.gg/" },
];

// Per-text answers from the building blocks, with the starter games listed.
page.reset(clone(DEFAULTS), { date: page.today(), results: {}, stale: [] }, null);
const texts = Object.entries(TEXTS).map(([name, text]) => {
  const head = page.headLine(text);
  return {
    name,
    text,
    headLine: head,
    findLink: page.findLink(text),
    titleOf: page.titleOf(head),
    guessGame: page.guessGame(text),
    looksLikeResult: page.looksLikeResult(text),
    stripLinks: page.stripLinks(text),
    mentioned: page.mentioned(text).map((g) => g.id),
    sharedTime: page.sharedTime(text),
    inMessage: MESSAGE_GAMES.map((g) => page.inMessage(g, text)),
  };
});

const urls = [
  "perceptle.com", "https://lessgames.com/songless", "globle-game.com/game", "nytimes.com/games/wordle",
  "https://www.nytimes.com/games/wordle/index.html", "chainle.io", "localhost", "  spotle.io  ",
  "HTTPS://Spotle.IO/Foo?x=1#y", "https://oec.world/en/tradle", "https://example.com/play/daily/123",
  "notaurl", "https://a.co/my_game-name", "http://Example.com:80/x", "https://example.com:8443/puzzles/",
  "lessgames.com/songless/", "https://www.immaculategrid.com/grid-300",
].map((input) => {
  const normalized = page.normalizeUrl(input);
  return { input, normalizeUrl: normalized, nameFromUrl: normalized ? page.nameFromUrl(normalized) : null };
});

const matchers = [
  ["Wordle", "Wordless 3/6"], ["Wordle", "wordle 3/6"], ["Waffle", "#waffle800"], ["Daily Tens", "DailyTens #1"],
  ["Tens", "Daily Tens #1"], ["Mini", "Minis 3"], ["NYT Mini", "nyt  mini 0:31"], ["Spotle", "Spotle.io #800"],
  ["C++", "C++ 3/6"], ["Pokédoku", "POKÉDOKU 9/9"], ["Krillion", "krillion.io"], ["Mini", "Mini2"],
  ["Daily Tens", "Daily Tens"], ["Strands", "“Strands” #1"],
].map(([name, text]) => ({ name, text, matches: page.matcher(name).test(text) }));

const wordle = { id: "gwordle", name: "Wordle", url: "https://www.nytimes.com/games/wordle/index.html" };
const connections = { id: "gconn", name: "Connections", url: "https://www.nytimes.com/games/connections" };
const withNyt = [...DEFAULTS, wordle, connections];
const renamed = DEFAULTS.map((g) => (g.id === "krillion" ? { ...g, name: "Krill", alias: "Krillion" } : g));
const T = TEXTS;
const combined = [T.spotle, T.perceptle].map(page.stripLinks).join("\n\n");

const scenarios = [
  ...Object.keys(T).map((name) => ({ name: `starter:${name}`, text: T[name] })),
  ...Object.keys(T).map((name) => ({ name: `empty:${name}`, games: [], text: T[name] })),
  ...["wordle", "bandle", "connections", "mini", "crossword", "worldle"].map((name) => ({ name: `nyt:${name}`, games: withNyt, text: T[name] })),
  { name: "two-games-named", games: withNyt, text: "Wordle and Connections today 🎉" },
  { name: "combined", results: { spotle: T.spotle, perceptle: T.perceptle }, text: combined },
  { name: "already-added", results: { spotle: T.spotle }, text: T.spotle },
  { name: "updated", results: { spotle: T.spotle }, text: T.spotle801 },
  { name: "stale", stale: [T.krillion], text: T.krillion },
  { name: "opened", lastOpened: "krillion", text: "🦐 4/6" },
  { name: "opened-done", lastOpened: "krillion", results: { krillion: T.krillion }, text: "🦐 4/6" },
  { name: "opened-guess", lastOpened: "perceptle", text: T.zip },
  { name: "renamed", games: renamed, text: T.krillion },
  { name: "link-into-listed", text: T.songlessLinkOnly },
];

const fixture = {
  generatedFrom: "index.html",
  defaults: DEFAULTS,
  messageGames: MESSAGE_GAMES,
  texts,
  urls,
  matchers,
  scenarios: scenarios.map((s) => ({
    name: s.name,
    games: s.games ?? null,
    results: s.results ?? {},
    stale: s.stale ?? [],
    lastOpened: s.lastOpened ?? null,
    text: s.text,
    outcome: run(s),
  })),
};

const out = join(here, "../DailyGamesTests/Fixtures/parity.json");
writeFileSync(out, JSON.stringify(fixture, null, 2) + "\n");
console.log(`Wrote ${fixture.texts.length} texts, ${fixture.urls.length} links, ${fixture.matchers.length} matchers, ${fixture.scenarios.length} scenarios to ${out}`);
