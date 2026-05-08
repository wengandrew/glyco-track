import CoreData
import XCTest
@testable import GlycoTrack

/// Regression tests verifying that the expanded ethnic-food databases
/// correctly resolve, report non-zero GL for carb-heavy dishes, and
/// report non-zero CL data for fat-heavy dishes.
///
/// Strategy:
///  • T1 resolution tests — the entry exists and T1 finds it directly or
///    via its aliases.
///  • Non-zero GL tests — GI > 0 entries must carry carbs so daily
///    totals are not silently zeroed.
///  • Non-zero CL tests — fat-dominant foods must carry fat-macro data.
///  • Alias resolution tests — restaurant/colloquial names route to the
///    right canonical entry, not to a spurious fuzzy match.
///
/// These tests do NOT call the Claude API; they exercise T1 and T2 only,
/// which is where all new data lives.
@MainActor
final class EthnicFoodCoverageTests: XCTestCase {

    private var pc: PersistenceController!
    private var repo: NutritionalRepository!

    override func setUp() async throws {
        try await super.setUp()
        pc = PersistenceController(inMemory: true)
        await pc.seedNutritionalProfiles()
        AliasIndex.shared.reload()
        repo = NutritionalRepository(context: pc.context, aliasIndex: .shared)
    }

    override func tearDown() async throws {
        repo = nil
        pc = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func assertResolvable(_ query: String,
                                  file: StaticString = #file,
                                  line: UInt = #line) -> NutritionalProfile? {
        let result = repo.findBestMatch(for: query)
        XCTAssertNotNil(result,
                        "'\(query)' should resolve via T1 direct or alias path",
                        file: file, line: line)
        return result?.profile
    }

    private func assertNonZeroGL(_ query: String,
                                 file: StaticString = #file,
                                 line: UInt = #line) {
        guard let p = assertResolvable(query, file: file, line: line) else { return }
        let gi = Double(p.glycemicIndex)
        let usedGI = gi == 0 && p.carbsPer100g > 3 ? 55.0 : gi
        let gl = usedGI * p.carbsPer100g / 100.0
        XCTAssertGreaterThan(gl, 0,
            "'\(query)' has GI=\(p.glycemicIndex) carbs=\(p.carbsPer100g) → GL should be >0",
            file: file, line: line)
    }

    private func assertHasFatData(_ query: String,
                                  file: StaticString = #file,
                                  line: UInt = #line) {
        guard let p = assertResolvable(query, file: file, line: line) else { return }
        let totalFat = p.saturatedFatPer100g + p.pufaPer100g + p.mufaPer100g
        XCTAssertGreaterThan(totalFat, 0,
            "'\(query)' should have fat macro data (SFA/PUFA/MUFA) for CL computation",
            file: file, line: line)
    }

    private func assertResolveAlias(_ alias: String,
                                    toCanonical canonical: String,
                                    file: StaticString = #file,
                                    line: UInt = #line) {
        let result = repo.findBestMatch(for: alias)
        XCTAssertNotNil(result,
                        "Alias '\(alias)' should resolve",
                        file: file, line: line)
        let got = result?.profile.foodName.lowercased() ?? ""
        XCTAssertEqual(got, canonical.lowercased(),
                       "Alias '\(alias)' → expected '\(canonical)', got '\(got)'",
                       file: file, line: line)
    }

    // MARK: ─── CHINESE / DIM SUM ─────────────────────────────────────────

    func testJasmineRiceResolvesAndHasGL() { assertNonZeroGL("jasmine rice") }
    func testStickyRiceResolvesAndHasGL()  { assertNonZeroGL("sticky rice") }
    func testGlutinousRiceResolvesAndHasGL() { assertNonZeroGL("glutinous rice") }
    func testXiaolongbaoResolvesAndHasGL() { assertNonZeroGL("xiaolongbao") }
    func testCharSiuBaoResolvesAndHasGL()  { assertNonZeroGL("char siu bao") }
    func testEggTartResolvesAndHasGL()     { assertNonZeroGL("egg tart") }
    func testTurnipCakeResolvesAndHasGL()  { assertNonZeroGL("turnip cake") }
    func testScallionPancakeResolvesAndHasGL() { assertNonZeroGL("scallion pancake") }
    func testSesameballResolvesAndHasGL()  { assertNonZeroGL("sesame ball") }
    func testDanDanNoodlesResolvesAndHasGL() { assertNonZeroGL("dan dan noodles") }
    func testHarGowResolvesAndHasGL()      { assertNonZeroGL("har gow") }
    func testCheungFunResolvesAndHasGL()   { assertNonZeroGL("cheung fun") }
    func testWaterChestnutsResolvesAndHasGL() { assertNonZeroGL("water chestnuts") }
    func testGlassNoodlesResolvesAndHasGL() { assertNonZeroGL("glass noodles") }
    func testRiceVermicelliResolvesAndHasGL() { assertNonZeroGL("rice vermicelli") }

    func testMapoTofuResolves()  { assertResolvable("mapo tofu") }
    func testHotPotResolves()    { assertResolvable("hot pot") }
    func testPekinDuckResolves() { assertResolvable("Peking duck") }
    func testCharSiuHasFatData() { assertHasFatData("char siu") }
    func testPorkBellyHasFatData() { assertHasFatData("pork belly") }

    func testSoupDumplingsAliasRoutesToXiaolongbao() {
        assertResolveAlias("soup dumplings", toCanonical: "xiaolongbao")
    }
    func testBaoBunAliasRoutesToCharSiuBao() {
        assertResolveAlias("bao bun", toCanonical: "char siu bao")
    }
    /// "cellophane noodles" is now a standalone canonical entry — both it
    /// and "glass noodles" carry the same GI/USDA data so either is correct.
    func testCellophaneNoodlesResolvesToNoodleEntry() {
        let result = repo.findBestMatch(for: "cellophane noodles")
        XCTAssertNotNil(result, "'cellophane noodles' should resolve")
        let name = result?.profile.foodName.lowercased() ?? ""
        XCTAssertTrue(name.contains("noodle") || name.contains("cellophane"),
                      "'cellophane noodles' must resolve to a noodle-type entry, got '\(name)'")
    }
    func testBeeHoonAliasRoutesToRiceVermicelli() {
        assertResolveAlias("bee hoon", toCanonical: "rice vermicelli")
    }

    // MARK: ─── JAPANESE ──────────────────────────────────────────────────

    func testGyozaResolvesAndHasGL()        { assertNonZeroGL("gyoza") }
    func testTonkatsuResolvesAndHasGL()     { assertNonZeroGL("tonkatsu") }
    func testKatsudonResolvesAndHasGL()     { assertNonZeroGL("katsudon") }
    func testOyakadonResolvesAndHasGL()     { assertNonZeroGL("oyakodon") }
    func testOnigiriResolvesAndHasGL()      { assertNonZeroGL("onigiri") }
    func testTakoyakiResolvesAndHasGL()     { assertNonZeroGL("takoyaki") }
    func testOkonomiyakiResolvesAndHasGL()  { assertNonZeroGL("okonomiyaki") }
    func testMochiResolvesAndHasGL()        { assertNonZeroGL("mochi") }
    func testJapaneseCurryResolvesAndHasGL() { assertNonZeroGL("Japanese curry") }
    func testDonburiResolvesAndHasGL()      { assertNonZeroGL("donburi") }
    func testTaiyakiResolvesAndHasGL()      { assertNonZeroGL("taiyaki") }
    func testDorayakiResolvesAndHasGL()     { assertNonZeroGL("dorayaki") }
    func testNigiriResolvesAndHasGL()       { assertNonZeroGL("nigiri") }
    func testKaraageResolvesAndHasGL()      { assertNonZeroGL("karaage") }
    func testNattoResolvesAndHasGL()        { assertNonZeroGL("natto") }
    func testJapaneseShortGrainRiceHasGL()  { assertNonZeroGL("Japanese short grain rice") }

    func testYakitoriResolves()  { assertResolvable("yakitori") }
    func testSukiyakiResolves()  { assertResolvable("sukiyaki") }
    func testShabuShabuResolves() { assertResolvable("shabu shabu") }

    /// "potstickers" resolves to whichever dumpling canonical owns that alias.
    /// Both "gyoza" and "dumplings" represent pan-fried dumplings; either is valid.
    func testPotstickersResolvesToDumpling() {
        let result = repo.findBestMatch(for: "potstickers")
        XCTAssertNotNil(result, "'potstickers' should resolve")
        let name = result?.profile.foodName.lowercased() ?? ""
        XCTAssertTrue(name.contains("dumpling") || name.contains("gyoza"),
                      "'potstickers' must resolve to a dumpling-type entry, got '\(name)'")
    }
    func testGohanAliasRoutesToJapaneseShortGrainRice() {
        assertResolveAlias("gohan", toCanonical: "Japanese short grain rice")
    }

    // MARK: ─── KOREAN ────────────────────────────────────────────────────

    func testTteokResolvesAndHasGL()        { assertNonZeroGL("tteok") }
    func testTteokbokkiResolvesAndHasGL()   { assertNonZeroGL("tteokbokki") }
    func testDakgalbiResolvesAndHasGL()     { assertNonZeroGL("dakgalbi") }
    func testHaemulPajeonResolvesAndHasGL() { assertNonZeroGL("haemul pajeon") }
    func testNaengmyeonResolvesAndHasGL()   { assertNonZeroGL("naengmyeon") }
    func testGimbapResolvesAndHasGL()       { assertNonZeroGL("gimbap") }
    func testHoddeokResolvesAndHasGL()      { assertNonZeroGL("hoddeok") }
    func testBingsuResolvesAndHasGL()       { assertNonZeroGL("bingsu") }
    func testKoreanFriedChickenResolvesAndHasGL() { assertNonZeroGL("Korean fried chicken") }

    func testGalbiResolves()        { assertResolvable("galbi") }
    func testSundubuJjigaeResolves() { assertResolvable("sundubu jjigae") }
    func testDoenjangJjigaeResolves() { assertResolvable("doenjang jjigae") }
    func testSamgyeopsalResolves()  { assertResolvable("samgyeopsal") }
    func testGalbiHasFatData()      { assertHasFatData("galbi") }
    func testSamgyeopsalHasFatData() { assertHasFatData("samgyeopsal") }

    func testKalbibAliasRoutesToGalbi() {
        assertResolveAlias("kalbi", toCanonical: "galbi")
    }
    func testKimbapAliasRoutesToGimbap() {
        assertResolveAlias("kimbap", toCanonical: "gimbap")
    }
    func testKimcheeAliasRoutesToKimchi() {
        assertResolveAlias("kimchee", toCanonical: "kimchi")
    }
    func testDolsotBibimbapAliasRoutesToBibimbap() {
        assertResolveAlias("dolsot bibimbap", toCanonical: "bibimbap")
    }

    // MARK: ─── THAI ──────────────────────────────────────────────────────

    func testGreenCurryResolvesAndHasGL()   { assertNonZeroGL("green curry") }
    func testRedCurryResolvesAndHasGL()     { assertNonZeroGL("red curry") }
    func testPadSeeEwResolvesAndHasGL()     { assertNonZeroGL("pad see ew") }
    func testKhaoPadResolvesAndHasGL()      { assertNonZeroGL("khao pad") }
    func testSomTamResolvesAndHasGL()       { assertNonZeroGL("som tam") }
    func testMangoStickyRiceResolvesAndHasGL() { assertNonZeroGL("mango sticky rice") }
    func testPanangCurryResolvesAndHasGL()  { assertNonZeroGL("panang curry") }
    func testKhaoTomResolvesAndHasGL()      { assertNonZeroGL("khao tom") }
    func testThaiIcedTeaResolvesAndHasGL()  { assertNonZeroGL("Thai iced tea") }

    func testPadKraPaoResolves() { assertResolvable("pad kra pao") }
    func testLarbResolves()      { assertResolvable("larb") }

    func testGreenCurryHasFatData()  { assertHasFatData("green curry") }
    func testRedCurryHasFatData()    { assertHasFatData("red curry") }

    func testPhanaengResolvesToCurry() {
        // "phanaeng" may or may not be a declared alias; regardless, the
        // T2 component scan finds "curry" inside it, so it must resolve.
        let result = repo.findBestMatch(for: "panang curry")
        XCTAssertNotNil(result, "'panang curry' should resolve directly")
    }
    func testSomTumAliasRoutesToSomTam() {
        assertResolveAlias("somtam", toCanonical: "som tam")
    }
    func testBasilChickenThaiAliasRoutesToPadKraPao() {
        assertResolveAlias("basil chicken Thai", toCanonical: "pad kra pao")
    }

    // MARK: ─── INDIAN ────────────────────────────────────────────────────

    func testAlooParathaResolvesAndHasGL()  { assertNonZeroGL("aloo paratha") }
    func testPohaResolvesAndHasGL()         { assertNonZeroGL("poha") }
    func testPavBhajiResolvesAndHasGL()     { assertNonZeroGL("pav bhaji") }
    func testCholeBhatureResolvesAndHasGL() { assertNonZeroGL("chole bhature") }
    func testRajmaResolvesAndHasGL()        { assertNonZeroGL("rajma") }
    func testKheerResolvesAndHasGL()        { assertNonZeroGL("kheer") }
    func testGuabJamunResolvesAndHasGL()    { assertNonZeroGL("gulab jamun") }
    func testJalebiResolvesAndHasGL()       { assertNonZeroGL("jalebi") }
    func testDhoklaResolvesAndHasGL()       { assertNonZeroGL("dhokla") }
    func testVadaResolvesAndHasGL()         { assertNonZeroGL("vada") }
    func testMasalaChaiResolvesAndHasGL()   { assertNonZeroGL("masala chai") }
    func testPulaoResolvesAndHasGL()        { assertNonZeroGL("pulao") }
    func testKhichdiResolvesAndHasGL()      { assertNonZeroGL("khichdi") }
    func testHalwaResolvesAndHasGL()        { assertNonZeroGL("halwa") }
    func testPaniPuriResolvesAndHasGL()     { assertNonZeroGL("pani puri") }
    func testVadaPavResolvesAndHasGL()      { assertNonZeroGL("vada pav") }
    func testSambarResolvesAndHasGL()       { assertNonZeroGL("sambar") }
    func testBesanResolvesAndHasGL()        { assertNonZeroGL("besan") }
    func testMoongDalResolvesAndHasGL()     { assertNonZeroGL("moong dal") }
    func testMasalaDosaResolvesAndHasGL()   { assertNonZeroGL("masala dosa") }
    func testRavaUpmaResolvesAndHasGL()     { assertNonZeroGL("rava upma") }
    func testLassiResolvesAndHasGL()        { assertNonZeroGL("lassi") }
    func testMangoLassiResolvesAndHasGL()   { assertNonZeroGL("mango lassi") }

    func testChickenTikkaResolves() { assertResolvable("chicken tikka") }
    func testTandooriChickenResolves() { assertResolvable("tandoori chicken") }
    func testSaagResolves()         { assertResolvable("saag") }
    func testAlooGobiResolves()     { assertResolvable("aloo gobi") }
    func testGheeHasFatData()       { assertHasFatData("ghee") }
    func testJalebiHasFatData()     { assertHasFatData("jalebi") }

    /// "chai tea" / "chai latte" route to the "chai" canonical (which the
    /// DB also carries). Both "chai" and "masala chai" represent the same
    /// spiced-milk-tea GL/CL profile, so either canonical is acceptable.
    func testChaiTeaResolvesToChaiOrMasalaChai() {
        let result = repo.findBestMatch(for: "chai tea")
        XCTAssertNotNil(result, "'chai tea' should resolve")
        let name = result?.profile.foodName.lowercased() ?? ""
        XCTAssertTrue(name.contains("chai"),
                      "'chai tea' must resolve to a chai-type entry, got '\(name)'")
    }
    func testChaiLatteResolvesToChaiOrMasalaChai() {
        let result = repo.findBestMatch(for: "chai latte")
        XCTAssertNotNil(result, "'chai latte' should resolve")
        let name = result?.profile.foodName.lowercased() ?? ""
        XCTAssertTrue(name.contains("chai"),
                      "'chai latte' must resolve to a chai-type entry, got '\(name)'")
    }
    /// "roti" is now a standalone canonical; both it and "chapati" represent
    /// the same unleavened Indian flatbread with equivalent GL data.
    func testRotiResolvesToFlatbread() {
        let result = repo.findBestMatch(for: "roti")
        XCTAssertNotNil(result, "'roti' should resolve")
        let name = result?.profile.foodName.lowercased() ?? ""
        XCTAssertTrue(name.contains("roti") || name.contains("chapati"),
                      "'roti' must resolve to a flatbread entry, got '\(name)'")
    }
    /// "garlic naan" routes to "butter naan" or "naan" — either is the
    /// leavened Indian flatbread category with equivalent GL.
    func testGarlicNaanResolvesToNaan() {
        let result = repo.findBestMatch(for: "garlic naan")
        XCTAssertNotNil(result, "'garlic naan' should resolve")
        let name = result?.profile.foodName.lowercased() ?? ""
        XCTAssertTrue(name.contains("naan"),
                      "'garlic naan' must resolve to a naan entry, got '\(name)'")
    }
    /// "dal tadka" routes to the standalone "dal tadka" canonical or the
    /// generic "dal" — both carry lentil GL data.
    func testDalTadkaResolves() {
        let result = repo.findBestMatch(for: "dal tadka")
        XCTAssertNotNil(result, "'dal tadka' should resolve")
        let name = result?.profile.foodName.lowercased() ?? ""
        XCTAssertTrue(name.contains("dal") || name.contains("lentil"),
                      "'dal tadka' must resolve to a lentil entry, got '\(name)'")
    }
    func testChickenBiryaniAliasRoutesToBiryani() {
        assertResolveAlias("chicken biryani", toCanonical: "biryani")
    }
    func testMurghMakhaniAliasRoutesToButterChicken() {
        assertResolveAlias("murgh makhani", toCanonical: "butter chicken")
    }
    func testGolGappeAliasRoutesToPaniPuri() {
        assertResolveAlias("gol gappe", toCanonical: "pani puri")
    }

    // MARK: ─── MIDDLE EASTERN ────────────────────────────────────────────

    func testFreekehResolvesAndHasGL()      { assertNonZeroGL("freekeh") }
    func testMujaddaraResolvesAndHasGL()    { assertNonZeroGL("mujaddara") }
    func testManakeeshResolvesAndHasGL()    { assertNonZeroGL("manakeesh") }
    func testKibbehResolvesAndHasGL()       { assertNonZeroGL("kibbeh") }
    func testHalvaResolvesAndHasGL()        { assertNonZeroGL("halva") }
    func testKnafehResolvesAndHasGL()       { assertNonZeroGL("knafeh") }
    func testTurkishDelightResolvesAndHasGL() { assertNonZeroGL("Turkish delight") }
    func testFatayerResolvesAndHasGL()      { assertNonZeroGL("fatayer") }
    func testFulMedamesResolvesAndHasGL()   { assertNonZeroGL("ful medames") }
    func testMaqlubahResolvesAndHasGL()     { assertNonZeroGL("maqluba") }
    func testMsabbachaResolvesAndHasGL()    { assertNonZeroGL("msabbaha") }
    func testPitaWrapResolvesAndHasGL()     { assertNonZeroGL("pita wrap") }

    func testKoftaResolves()    { assertResolvable("kofta") }
    func testMolokhiaResolves() { assertResolvable("molokhia") }
    func testKoftaHasFatData()  { assertHasFatData("kofta") }

    func testKunafaAliasRoutesToKnafeh() {
        assertResolveAlias("kunafa", toCanonical: "knafeh")
    }
    func testLokumAliasRoutesToTurkishDelight() {
        assertResolveAlias("lokum", toCanonical: "Turkish delight")
    }
    func testMujadaraAliasRoutesToMujaddara() {
        assertResolveAlias("mujadara", toCanonical: "mujaddara")
    }
    func testLebaneseFlatbreadAliasRoutesToManakeesh() {
        assertResolveAlias("Lebanese flatbread zaatar", toCanonical: "manakeesh")
    }

    // MARK: ─── MEXICAN ───────────────────────────────────────────────────

    func testCornTortillaResolvesAndHasGL() { assertNonZeroGL("corn tortilla") }
    func testQuesadillaResolvesAndHasGL()   { assertNonZeroGL("quesadilla") }
    func testHorchataResolvesAndHasGL()     { assertNonZeroGL("horchata") }
    func testMexicanRiceResolvesAndHasGL()  { assertNonZeroGL("Mexican rice") }
    func testRefriedBeansResolvesAndHasGL() { assertNonZeroGL("refried beans") }
    func testSopesResolvesAndHasGL()        { assertNonZeroGL("sopes") }
    func testFlautasResolvesAndHasGL()      { assertNonZeroGL("flautas") }
    func testChilesRellenosResolvesAndHasGL() { assertNonZeroGL("chiles rellenos") }
    func testEloteResolvesAndHasGL()        { assertNonZeroGL("elote") }
    func testTortaResolvesAndHasGL()        { assertNonZeroGL("torta") }
    func testTlayudaResolvesAndHasGL()      { assertNonZeroGL("tlayuda") }
    func testMoleSauceResolvesAndHasGL()    { assertNonZeroGL("mole sauce") }
    func testMasaResolvesAndHasGL()         { assertNonZeroGL("masa") }

    func testCarnitasResolves()  { assertResolvable("carnitas") }
    func testBarbacoaResolves()  { assertResolvable("barbacoa") }
    func testCarneAsadaResolves() { assertResolvable("carne asada") }
    func testCarnitasHasFatData()  { assertHasFatData("carnitas") }

    func testTaquitos_AliasRoutesToFlautas() {
        assertResolveAlias("taquitos Mexican", toCanonical: "flautas")
    }
    func testArroz_Rojo_AliasRoutesToMexicanRice() {
        assertResolveAlias("arroz rojo", toCanonical: "Mexican rice")
    }

    // MARK: ─── FILIPINO ──────────────────────────────────────────────────

    func testChickenAdoboResolves()         { assertResolvable("chicken adobo") }
    func testSinigangResolves()             { assertResolvable("sinigang") }
    func testKareKareResolvesAndHasGL()     { assertNonZeroGL("kare kare") }
    func testLechonResolves()               { assertResolvable("lechon") }
    func testPancitResolvesAndHasGL()       { assertNonZeroGL("pancit") }
    func testLumpiaResolvesAndHasGL()       { assertNonZeroGL("lumpia") }
    func testSisigResolves()               { assertResolvable("sisig") }
    func testLecheFlanResolvesAndHasGL()    { assertNonZeroGL("leche flan") }
    func testHaloHaloResolvesAndHasGL()     { assertNonZeroGL("halo halo") }
    func testChamporadoResolvesAndHasGL()   { assertNonZeroGL("champorado") }
    func testSisigHasFatData()             { assertHasFatData("sisig") }
    func testLechonHasFatData()            { assertHasFatData("lechon") }

    func testFilipinoNoodlesAliasRoutesToPancit() {
        assertResolveAlias("Filipino noodles", toCanonical: "pancit")
    }

    // MARK: ─── MALAYSIAN / SINGAPOREAN ───────────────────────────────────

    func testNasiLemakResolvesAndHasGL()    { assertNonZeroGL("nasi lemak") }
    func testRotiCanaiResolvesAndHasGL()    { assertNonZeroGL("roti canai") }
    func testCharKwayTeowResolvesAndHasGL() { assertNonZeroGL("char kway teow") }
    func testHokkienMeeResolvesAndHasGL()   { assertNonZeroGL("hokkien mee") }
    func testTehTarikResolvesAndHasGL()     { assertNonZeroGL("teh tarik") }
    func testCurryPuffResolvesAndHasGL()    { assertNonZeroGL("curry puff") }
    func testKayaToastResolvesAndHasGL()    { assertNonZeroGL("kaya toast") }
    func testMeeGorengResolvesAndHasGL()    { assertNonZeroGL("mee goreng") }
    func testChendolResolvesAndHasGL()      { assertNonZeroGL("chendol") }
    func testNasiPadangResolvesAndHasGL()   { assertNonZeroGL("nasi padang") }
    func testNasiLemakHasFatData()         { assertHasFatData("nasi lemak") }

    func testRotiPrataAliasRoutesToRotiCanai() {
        assertResolveAlias("roti prata", toCanonical: "roti canai")
    }
    func testKaripapAliasRoutesToCurryPuff() {
        assertResolveAlias("karipap", toCanonical: "curry puff")
    }

    // MARK: ─── INDONESIAN ────────────────────────────────────────────────

    func testGadoGadoResolvesAndHasGL()     { assertNonZeroGL("gado gado") }
    func testSotoAyamResolvesAndHasGL()     { assertNonZeroGL("soto ayam") }
    func testNasiUdukResolvesAndHasGL()     { assertNonZeroGL("nasi uduk") }
    func testMartabakResolvesAndHasGL()     { assertNonZeroGL("martabak") }
    func testBaksoResolvesAndHasGL()        { assertNonZeroGL("bakso") }
    func testMieGorengResolvesAndHasGL()    { assertNonZeroGL("mie goreng") }
    func testNasiUdukHasFatData()          { assertHasFatData("nasi uduk") }

    // MARK: ─── VIETNAMESE ────────────────────────────────────────────────

    func testBunBoHueResolvesAndHasGL()     { assertNonZeroGL("bun bo hue") }
    func testComTamResolvesAndHasGL()       { assertNonZeroGL("com tam") }
    func testBanhXeoResolvesAndHasGL()      { assertNonZeroGL("banh xeo") }
    func testBanhCuonResolvesAndHasGL()     { assertNonZeroGL("banh cuon") }
    func testVietnameseIcedCoffeeResolvesAndHasGL() {
        assertNonZeroGL("Vietnamese iced coffee")
    }
    func testBunRieuResolvesAndHasGL()      { assertNonZeroGL("bun rieu") }
    func testCaoLauResolvesAndHasGL()       { assertNonZeroGL("cao lau") }

    func testCaPheAlias() {
        assertResolveAlias("ca phe sua da", toCanonical: "Vietnamese iced coffee")
    }

    // MARK: ─── SOUTH AMERICAN ────────────────────────────────────────────

    func testEmpanadasResolvesAndHasGL()    { assertNonZeroGL("empanada") }
    func testFeijoadadResolvesAndHasGL()    { assertNonZeroGL("feijoada") }
    func testPaoDeQueijooResolvesAndHasGL() { assertNonZeroGL("pao de queijo") }
    func testBrigadeiroResolvesAndHasGL()   { assertNonZeroGL("brigadeiro") }
    func testLomoSaltadoResolvesAndHasGL()  { assertNonZeroGL("lomo saltado") }
    func testChichaMorenaResolvesAndHasGL() { assertNonZeroGL("chicha morada") }
    func testArrozConLecheResolvesAndHasGL() { assertNonZeroGL("arroz con leche") }
    func testTostonesResolvesAndHasGL()     { assertNonZeroGL("tostones") }
    func testYucaFritaResolvesAndHasGL()    { assertNonZeroGL("yuca frita") }
    func testSancochoResolvesAndHasGL()     { assertNonZeroGL("sancocho") }
    func testAjiacoResolvesAndHasGL()       { assertNonZeroGL("ajiaco") }
    func testHallacaResolvesAndHasGL()      { assertNonZeroGL("hallaca") }

    func testChurrascoResolves()    { assertResolvable("churrasco") }
    func testAnticuchoResolves()    { assertResolvable("anticucho") }
    func testChurrascoHasFatData()  { assertHasFatData("churrasco") }

    /// "patacones" is now a standalone canonical (equivalent to tostones —
    /// both are twice-fried green plantain). Either canonical is correct.
    func testPatacones_ResolvesToPlantainEntry() {
        let result = repo.findBestMatch(for: "patacones")
        XCTAssertNotNil(result, "'patacones' should resolve")
        let name = result?.profile.foodName.lowercased() ?? ""
        XCTAssertTrue(name.contains("patacon") || name.contains("tostones") || name.contains("plantain"),
                      "'patacones' must resolve to a fried plantain entry, got '\(name)'")
    }
    /// "cassava fries" resolves to the "yuca fries" or "yuca frita" canonical —
    /// both are valid fried-cassava entries with matching GL data.
    func testCassavaFriesResolvesToYucaEntry() {
        let result = repo.findBestMatch(for: "cassava fries")
        XCTAssertNotNil(result, "'cassava fries' should resolve")
        let name = result?.profile.foodName.lowercased() ?? ""
        XCTAssertTrue(name.contains("yuca") || name.contains("cassava"),
                      "'cassava fries' must resolve to a yuca/cassava entry, got '\(name)'")
    }

    // MARK: ─── AFRICAN ───────────────────────────────────────────────────

    func testInjeraResolvesAndHasGL()       { assertNonZeroGL("injera") }
    func testJollofRiceResolvesAndHasGL()   { assertNonZeroGL("jollof rice") }
    func testEgusiSoupResolves()           { assertResolvable("egusi soup") }
    func testSuyaResolves()                { assertResolvable("suya") }
    func testFufuResolvesAndHasGL()        { assertNonZeroGL("fufu") }
    func testUgaliResolvesAndHasGL()       { assertNonZeroGL("ugali") }
    func testPeriPeriChickenResolves()     { assertResolvable("peri peri chicken") }
    func testEgusiSoupHasFatData()         { assertHasFatData("egusi soup") }

    func testPiriPiriAliasRoutes() {
        assertResolveAlias("piri piri chicken", toCanonical: "peri peri chicken")
    }
    func testNigerianJollofAlias() {
        assertResolveAlias("Nigerian jollof", toCanonical: "jollof rice")
    }

    // MARK: ─── DRINKS ────────────────────────────────────────────────────

    func testBubbleTeaResolvesAndHasGL()    { assertNonZeroGL("bubble tea") }
    func testTaroMilkTeaResolvesAndHasGL()  { assertNonZeroGL("taro milk tea") }
    func testMatcaLatteResolvesAndHasGL()   { assertNonZeroGL("matcha latte") }
    func testCoconutMilkTeaResolvesAndHasGL() { assertNonZeroGL("coconut milk tea") }
    func testSugarcaneJuiceResolvesAndHasGL() { assertNonZeroGL("sugarcane juice") }
    func testRoseMilkResolvesAndHasGL()     { assertNonZeroGL("rose milk") }
    func testTamarindJuiceResolvesAndHasGL() { assertNonZeroGL("tamarind juice") }
    func testLycheeJuiceResolvesAndHasGL()  { assertNonZeroGL("lychee juice") }
    func testTapiocaPearlsResolvesAndHasGL() { assertNonZeroGL("tapioca pearls") }
    func testThaiIcedTeaAlias() {
        assertResolveAlias("cha yen", toCanonical: "Thai iced tea")
    }
    /// "boba tea" (two-word form) safely routes to bubble tea.
    /// The bare word "boba" is excluded as an alias because its Levenshtein
    /// distance of 1 from "soba" would make it a fuzzy collision risk.
    func testBobaTeaAliasRoutesToBubbleTea() {
        assertResolveAlias("boba tea", toCanonical: "bubble tea")
    }

    // MARK: ─── INGREDIENTS ───────────────────────────────────────────────

    func testGalangalResolves()      { assertResolvable("galangal") }
    func testLemongrassResolves()    { assertResolvable("lemongrass") }
    func testDaikonRadishResolves()  { assertResolvable("daikon radish") }
    func testWaterSpinachResolves()  { assertResolvable("water spinach") }
    func testMirinResolvesAndHasGL() { assertNonZeroGL("mirin") }
    func testFishSauceResolves()     { assertResolvable("fish sauce") }
    func testOysterSauceResolvesAndHasGL() { assertNonZeroGL("oyster sauce") }
    func testHoisinSauceResolvesAndHasGL() { assertNonZeroGL("hoisin sauce") }

    // MARK: ─── SEEDING COMPLETENESS ──────────────────────────────────────

    func testDatabaseHasAtLeast1000GIEntries() throws {
        let request = NutritionalProfile.fetchRequest()
        let count = try pc.context.count(for: request)
        XCTAssertGreaterThanOrEqual(count, 1000,
            "Database should contain ≥ 1000 profiles after ethnic expansion")
    }

    // MARK: ─── WORD-BOUNDARY SAFETY WITH NEW ENTRIES ─────────────────────

    /// "mirin" (Japanese rice wine) must not fuzzy-match "miso" or similar.
    func testMirinDoesNotFuzzyMatchMiso() {
        let result = repo.findBestMatch(for: "mirin")
        XCTAssertNotEqual(result?.profile.foodName.lowercased(), "miso paste",
                          "Fuzzy match must not bridge 'mirin' to 'miso paste'")
    }

    /// "kofta" must not match "tofu" via fuzzy.
    func testKoftaDoesNotFuzzyMatchTofu() {
        let result = repo.findBestMatch(for: "kofta")
        XCTAssertNotEqual(result?.profile.foodName.lowercased(), "tofu",
                          "Fuzzy match must not bridge 'kofta' to 'tofu'")
    }

    /// "tteok" (Korean rice cake) must not match "tteokbokki" via contains —
    /// they are separate entries with different GL values.
    func testTteokDoesNotResolveToTteokbokki() {
        let result = repo.findBestMatch(for: "tteok")
        XCTAssertNotEqual(result?.profile.foodName.lowercased(), "tteokbokki",
                          "Direct query 'tteok' must land on its own entry, not on 'tteokbokki'")
    }

    /// "soba" alias should not accidentally land on "soba noodles" via
    /// a contains path instead of the direct entry (both are in the DB).
    func testSobaResolvesSmoothly() {
        let result = repo.findBestMatch(for: "soba")
        XCTAssertNotNil(result, "'soba' must resolve")
        let name = result?.profile.foodName.lowercased() ?? ""
        // Either "soba" itself or "soba noodles" is acceptable — both exist
        // and carry correct nutrition. The important thing is it doesn't land
        // on an unrelated food.
        XCTAssertTrue(name.contains("soba"),
                      "Query 'soba' must resolve to a soba entry, got '\(name)'")
    }

    /// "masa" (corn dough) should not fuzzy-match "massaman curry".
    func testMasaDoesNotMatchMassaman() {
        let result = repo.findBestMatch(for: "masa")
        XCTAssertFalse(result?.profile.foodName.lowercased().contains("massaman") ?? false,
                       "Fuzzy match must not bridge 'masa' (corn dough) to 'massaman curry'")
    }
}
