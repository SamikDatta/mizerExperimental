test_that("projectToSteady() works", {
    params <- NS_params
    initialN(params)[1, ] <- initialN(params)[1, ] * 3
    expect_error(projectToSteady(NS_params, dt = 1, t_per = 0.5),
                 "t_per must be a positive multiple of dt")
    expect_error(projectToSteady(NS_params, t_max = 0.1),
                   "t_max not greater than or equal to t_per")
    expect_message(projectToSteady(params, t_max = 0.1, t_per = 0.1),
                   "Simulation run did not converge after 0.1 years.")
    expect_message(paramsc <- projectToSteady(params, tol = 10),
                   "Convergence was achieved in 4.5 years")
    expect_s4_class(paramsc, "MizerParams")
    # shouldn't take long the second time we run to steady
    expect_message(projectToSteady(paramsc, tol = 10),
                   "Convergence was achieved in 1.5 years")

    # return sim
    expect_message(sim <- projectToSteady(params, return_sim = TRUE, tol = 10),
                   "Convergence was achieved in 4.5 years")
    expect_s4_class(sim, "MizerSim")

    # Alternative distance function
    expect_message(paramsc <- projectToSteady(params,
                                              distance_func = distanceMaxRelRDI,
                                              tol = 0.1),
                   "Convergence was achieved in 9 years.")
    # shouldn't take long the second time we run to steady
    expect_message(projectToSteady(paramsc,
                                   distance_func = distanceMaxRelRDI,
                                   tol = 0.1),
                   "Convergence was achieved in 1.5 years")

    # Check extinction
    params@psi[5:6, ] <- 0
    expect_warning(projectToSteady(params),
                   "Dab, Whiting are going extinct.")
})

# steady ----
# This is needed only as long as we duplicate `steady()` in mizerExperimental
# until `projectToSteady()` has moved to core mizer.
test_that("steady works", {
    expect_message(params <- newTraitParams(no_sp = 4, no_w = 30, R_factor = Inf,
                                            n = 2/3, lambda = 2 + 3/4 - 2/3,
                                            max_w_inf = 1e3, min_w = 1e-4,
                                            w_pp_cutoff = 10, ks = 4),
                   "Increased no_w to 36")
    params@species_params$gamma[2] <- 2000
    params <- setSearchVolume(params)
    p <- steady(params, t_per = 2)
    p_mizer <- mizer::steady(params, t_per = 2)
    expect_identical(p, p_mizer)
    # and works the same when returning sim
    sim <- steady(params, t_per = 2, return_sim = TRUE)
    sim_mizer <- mizer::steady(params, t_per = 2, return_sim = TRUE)
    expect_identical(sim, sim_mizer)
})
