library(mizer)

# markBackground() ----
test_that("markBackground() works", {
    params <- markBackground(NS_params, species = "Cod")
    expect_identical(params@A[[11]], NA_real_)
    params <- markBackground(NS_params, species = c("Cod", "Dab"))
    expect_identical(params@A[[5]], NA_real_)
    sim <- markBackground(project(NS_params, t_max = 0.1))
    expect_true(all(is.na(sim@params@A)))
    expect_error(markBackground(1),
                 "The `object` argument must be of type MizerParams or MizerSim.")
})

# removeSpecies ----
test_that("removeSpecies works", {
    remove <- NS_species_params$species[2:11]
    reduced <- NS_species_params[!(NS_species_params$species %in% remove), ]
    params <- MizerParams(NS_species_params, no_w = 20,
                          max_w = 39900, min_w_pp = 9e-14)
    p1 <- removeSpecies(params, species = remove)
    expect_equal(nrow(p1@species_params), nrow(params@species_params) - 10)
    p2 <- MizerParams(reduced, no_w = 20,
                      max_w = 39900, min_w_pp = 9e-14)
    expect_equivalent(p1, p2)
    sim1 <- project(p1, t_max = 0.4, t_save = 0.4)
    sim2 <- project(p2, t_max = 0.4, t_save = 0.4)
    expect_identical(sim1@n[2, 2, ], sim2@n[2, 2, ])
})
test_that("removeSpecies works with 3d pred kernel", {
    # It should make no difference whether we first set full pred kernel and
    # then remove a species, or the other way around.
    params1 <- NS_params
    params1 <- setPredKernel(params1, pred_kernel = getPredKernel(params1))
    params1 <- removeSpecies(params1, "Cod")
    params2 <- NS_params
    params2 <- removeSpecies(params2, "Cod")
    params2 <- setPredKernel(params2, pred_kernel = getPredKernel(params2))
    expect_identical(params1, params2)
})
test_that("removeSpecies works correctly on gear_params", {
    # We'll check that the resulting gear_params lead to the same selectivity
    # and catchability
    params <- removeSpecies(NS_params, "Cod")
    expect_equal(nrow(params@gear_params), 11)
    params2 <- setFishing(params)
    expect_identical(params, params)
})


# pruneSpecies() removes low-abundance species ----
test_that("pruneSpecies() removes low-abundance species", {
    params <- newTraitParams()
    p <- params
    # We multiply one of the species by a factor of 10^-4 and expect
    # pruneSpecies() to remove it.
    p@initial_n[5, ] <- p@initial_n[5, ] * 10^-4
    p <- pruneSpecies(p, 10^-2)
    expect_is(p, "MizerParams")
    expect_equal(nrow(params@species_params) - 1, nrow(p@species_params))
    expect_equal(p@initial_n[5, ], params@initial_n[6, ])
})

# retuneBackground() ----
test_that("retuneBackground", {
    expect_message(retuneBackground(NS_params),
                   "There are no background species left.")
})

test_that("retuneBackground() removes Cod", {
    params <- markBackground(NS_params, species = "Cod")
    expect_message(params <- retuneBackground(params),
                   "There are no background species left.")
})

test_that("retuneBackground() reproduces scaling model", {
    # This numeric test failed on Solaris and without long doubles. So for now
    # skipping it on CRAN
    skip_on_cran()
    p <- newTraitParams(n = 2/3, lambda = 2 + 3/4 - 2/3) # q = 3/4
    initial_n <- p@initial_n
    # We multiply one of the species by a factor of 5 and expect
    # retuneBackground() to tune it back down to the original value.
    p@initial_n[5, ] <- 5 * p@initial_n[5, ]
    pr <- p %>%
        markBackground() %>%
        retuneBackground()
    expect_lt(max(abs(initial_n - pr@initial_n)), 2e-11)
})


# addSpecies ----
test_that("addSpecies works when adding a second identical species", {
    p <- newTraitParams()
    no_sp <- length(p@A)
    p <- markBackground(p)
    species_params <- p@species_params[5,]
    species_params$species = "new"
    # Adding species 5 again should lead two copies of the species
    pa <- addSpecies(p, species_params)
    expect_identical(pa@metab[5, ], pa@metab[no_sp+1, ])
    expect_identical(pa@psi[5, ], pa@psi[no_sp+1, ])
    expect_identical(pa@ft_pred_kernel_e[5, ], pa@ft_pred_kernel_e[no_sp+1, ])

    # test that we can remove species again
    pr <- removeSpecies(pa, "new")

})
test_that("addSpecies does not allow duplicate species", {
    p <- NS_params
    species_params <- p@species_params[5, ]
    expect_error(addSpecies(p, species_params),
                 "You can not add species that are already there.")
})
test_that("addSpecies handles gear params correctly", {
    p <- newTraitParams(no_sp = 2)
    sp <- data.frame(species = c("new1", "new2"),
                     w_inf = c(10, 100),
                     k_vb = c(1, 1),
                     n = 2/3,
                     p = 2/3)
    gp <- data.frame(gear = c("gear1", "gear2", "gear1"),
                     species = c("new1", "new2", "new2"),
                     sel_func = "knife_edge",
                     knife_edge_size = c(5, 5, 50))

    pa <- addSpecies(p, sp, gp)
    effort = c(knife_edge_gear = 0, gear1 = 0, gear2 = 0)
    expect_identical(pa@initial_effort, effort)
    expect_identical(nrow(pa@gear_params), 5L)

    effort = c(knife_edge_gear = 1, gear1 = 2, gear2 = 3)
    pa <- addSpecies(p, sp, gp, initial_effort = effort)
    expect_identical(pa@initial_effort, effort)

    extra_effort = c(gear1 = 2, gear2 = 3)
    pa <- addSpecies(p, sp, gp, initial_effort = extra_effort)
    expect_identical(pa@initial_effort, c(knife_edge_gear = 0, extra_effort))

    effort = 2
    expect_error(addSpecies(p, sp, gp, initial_effort = effort),
                 "The `initial_effort` must be a named list or vector")

    effort = c(gear3 = 1)
    expect_error(addSpecies(p, sp, gp, initial_effort = effort),
                 "The names of the `initial_effort` do not match the names of gears.")
})

test_that("addSpecies handles interaction matrix correctly", {
    p <- newTraitParams(no_sp = 2)
    p <- setInteraction(p, interaction = matrix(1:4/8, ncol = 2))
    sp <- data.frame(species = c("new1", "new2"),
                     w_inf = c(10, 100),
                     k_vb = c(1, 1),
                     n = 2/3,
                     p = 2/3)

    interaction = matrix(1:4/4, ncol = 2)
    ones = matrix(rep(1, 4), ncol = 2)
    pa <- addSpecies(p, sp, interaction = interaction)
    expect_equivalent(pa@interaction[3:4, 3:4], interaction)
    expect_equivalent(pa@interaction[1:2, 3:4], ones)
    expect_equivalent(pa@interaction[3:4, 1:2], ones)
    expect_equivalent(pa@interaction[1:2, 1:2], p@interaction)

    interaction = matrix(1:16/16, ncol = 4)
    pa <- addSpecies(p, sp, interaction = interaction)
    expect_equivalent(pa@interaction, interaction)

    expect_error(addSpecies(p, sp,
                            interaction = matrix(1:9, ncol = 3)),
                 "Interaction matrix has invalid dimensions.")
})


test_that("adding and then removing species leaves params unaltered", {
    params <- NS_params
    # TODO: currently NS_params still has factors in gear_params
    params@gear_params$species <- as.character(params@gear_params$species)
    params@gear_params$gear <- as.character(params@gear_params$gear)
    # add comments to test that they will be preserved as well
    comment(params) <- "test"
    for (slot in (slotNames(params))) {
        comment(slot(params, slot)) <- slot
    }
    # two arbitrary species
    sp <- data.frame(species = c("new1", "new2"),
                     w_inf = c(10, 100),
                     k_vb = c(1, 1),
                     stringsAsFactors = FALSE)
    params2 <- addSpecies(params, sp) %>%
        removeSpecies(c("new1", "new2"))

    # For now the linecolour and linetype are not preserved
    # TODO: fix this in the next overhaul of linecolour and linetype code
    params2@linecolour <- params@linecolour
    params2@linetype <- params@linetype
    params2@species_params$linecolour <- NULL
    params2@species_params$linetype <- NULL
    # Currently addSpecies still changes RDD
    # TODO: fix this
    params2@rates_funcs$RDD <- params@rates_funcs$RDD
    # comment on w_min_idx are not preserved
    comment(params@w_min_idx) <- NULL
    expect_equal(params, params2)
})

test_that("addSpecies works when adding a species with a larger w_inf", {
    
    # Set up North Sea parameters
    params <- newMultispeciesParams(NS_species_params_gears, inter)
    
    # Try adding species with bigger w_inf
    
    species_params <- data.frame(species = "Blue whale", w_inf = 5e4, w_mat = 1e3, beta = 1000, sigma = 2, k_vb = 0.6, 
                                 gear = 'Whale hunter')
    
    inter = inter[c(1:12, 1), c(1:12, 1)] # use interactions of sprat to be lazy
    colnames(inter)[13] = 'Blue whale'
    rownames(inter)[13] = 'Blue whale' # make sure row and column names match the species name
    p_temp = addSpecies(params, species_params, interaction = inter) # add species - no crash
    
})

# retuneReproductiveEfficiency ----
test_that("retuneReproductiveEfficiency works", {
    p <- newTraitParams(R_factor = Inf)
    no_sp <- nrow(p@species_params)
    erepro <- p@species_params$erepro
    p@species_params$erepro[5] <- 15
    ps <- retune_erepro(p)
    expect_equal(ps@species_params$erepro, erepro)
    # can also select species in various ways
    ps <- retune_erepro(p, species = p@species_params$species[5])
    expect_equal(ps@species_params$erepro, erepro)
    p@species_params$erepro[3] <- 15
    species <- (1:no_sp) %in% c(3,5)
    ps <- retune_erepro(p, species = species)
    expect_equal(ps@species_params$erepro, erepro)
})

# renameSpecies ----
test_that("renameSpecies works", {
    sp <- NS_species_params
    p <- newMultispeciesParams(sp)
    sp$species <- tolower(sp$species)
    replace <- NS_species_params$species
    names(replace) <- sp$species
    p2 <- newMultispeciesParams(sp)
    p2 <- renameSpecies(p2, replace)
    expect_identical(p, p2)
})
test_that("renameSpecies warns on wrong names", {
    expect_error(renameSpecies(NS_params, c(Kod = "cod", Hadok = "haddock")),
                 "Kod, Hadok do not exist")
})

# rescaleAbundance ----
test_that("rescaleAbundance works", {
    p <- retune_erepro(NS_params)
    factor <- c(Cod = 2, Haddock = 3)
    p2 <- rescaleAbundance(NS_params, factor)
    expect_identical(p@initial_n["Cod"] * 2, p2@initial_n["Cod"])
    expect_equal(p, rescaleAbundance(p2, 1/factor))
})
test_that("rescaleAbundance throws correct error",{
    expect_error(rescaleAbundance(NS_params, c(2, 3)))
    expect_error(rescaleAbundance(NS_params, "a"))
})
test_that("rescaleAbundance warns on wrong names", {
    expect_error(rescaleAbundance(NS_params, c(Kod = 2, Hadok = 3)),
                 "Kod, Hadok do not exist")
})

# rescaleSystem ----
test_that("rescaleSystem does not change dynamics.", {
    factor <- 10
    sim <- project(NS_params, t_max = 1)
    params2 <- rescaleSystem(NS_params, factor)
    sim2 <- project(params2, t_max = 1)
    expect_equal(sim2@n[1, , ], sim@n[1, , ] * factor)
    expect_equal(sim2@n[2, , ], sim@n[2, , ] * factor)
})
