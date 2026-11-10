// This script styles a Stata plot with a LaTeX-friendly typeface.
// An MCMC traceplot of regression for a water quality dataset is generated.
// The traceplot is output in SVG format (and PDF if Inkscape is available).


// Define utility macros and programs.

local success = 0

capture program drop normalise_slashes    // Drop any existing definition.
program define normalise_slashes, rclass

    // This program block converts "\" to "/" in file paths.
    //     - Stata supports "/" delimiters on all operating systems.
    //     - Using "/" avoids unwanted runtime escape character interpretation.

    syntax [anything]

    if missing(`"`anything'"') {
        return local normalised_val ""
    }
    else {
        // Perform...
        // - triple delimiter transforms for some mapped network paths, then,
        // - general single delimiter transforms.

        return local normalised_val ///
            = subinstr(subinstr(`anything', "\\\", "//", .), "\", "/", .)
    }

end


capture program drop prepare_exit    // Drop any existing definition.
program define prepare_exit

    // This program block prepares to exit the script gracefully.
    //     - Global macros not needed elsewhere are dropped.
    //     - An optional input exiting message is displayed.
    // N.B. An "exit" call in the block will only exit the block, not script.

    syntax [anything]

    macro drop glb_data_full_path

    // Display any input exiting message.
    if !missing(`"`anything'"') {
        display `"`anything'"'
    }
end


// Import water quality data from the file "water-quality.csv".
// Imported variables:
//
//    Name            Type    Units   Description
//    ----            ----    -----   -----------
//    catchment       float   km^2    Catchment area.
//    quality         float   IBI     Water quality.
//    log_catchment   float   -       Log, base 10, of the catchment area value.
//
//  N.B. IBI is index of biological integrity. High values indicate good water 
//  quality, low values represent poor water quality.

// Prompt the user to select water quality data (CSV file) to import.
// N.B. "window fopen" returns a global.
macro drop glb_data_full_path   // Drop any values left from other sessions.
capture window fopen glb_data_full_path "Select Water Quality Dataset" ///
    "Comma-Separated Values (*.csv)|*.csv" csv
if _rc != `success' {
    prepare_exit "No dataset selected, exiting."
    exit
}

// Ensure the file "water-quality.csv" was selected.
local target_file "water-quality.csv"
mata: st_local("data_file", pathbasename("${glb_data_full_path}"))
if "`data_file'" != "`target_file'" {
    prepare_exit "Invalid file: `data_file'. Expected `target_file', exiting."
    exit
}


// File path management.
normalise_slashes "${glb_data_full_path}"
global glb_data_full_path = r(normalised_val)
local data_parent_directory = subinstr("${glb_data_full_path}", ///
    "`target_file'", "", .)


// Import the water quality data, replacing data already in memory (if any).
capture import delimited "${glb_data_full_path}", clear
if _rc != `success' {
    prepare_exit "Unable to import data from ${glb_data_full_path}, exiting."
    exit
}


// Perform Bayesian linear regression of water quality (units).
//
//     - Dots were output to the display as progress indicators.
//     - Four chains were used.
//     - A random seed was used for reproducible results.
//     - Results were saved to "simdata.dta".
//           (Stata data files use a ".dta" extension.)
//
// N.B. Stata's default prior distributions:
//
//     - regression coefficients: normal(0,10000)
//           i.e. normal of mean = 0 and variance = 10,000.
//
//     - variance: igamma(0.01,0.01)
//           i.e. inverse-gamma with scale = 0.01 and shape = 0.01.
//
// N.B. Stata's default MCMC parameters are:
//
//     - MCMC iterations: 12,500.
//     - Burn-in: 2,500.
//
//     Here, 15,000 MCMC iterations (and 3,000 burn-in) were used.
//     The increased burn-in period, compared with the Stata default, addressed
//     an issue with adaptation tolerance.
//
bayes, burnin(3000) dots(1000) mcmcsize(15000) nchains(4) rseed(117) ///
    saving("`data_parent_directory'simdata", replace): ///
    regress quality log_catchment


// Set the default graphics typeface to an implementation of Computer Modern.
// This is done for visual harmony with LaTeX documents.
// N.B. If the specified typeface isn't available, Stata will use a default
//      sans-serif typeface instead.
local custom_typeface "CMU Serif"
graph set window fontface "`custom_typeface'"

// Disable printing of the Stata logo on exported graphs.
graph set print logo off

// Display a traceplot for the first chain.
// N.B. Use 'note("")' to disable the chain label.
//
bayesgraph trace {quality:log_catchment}, chains(1) lcolor(black) note("") ///
    graphregion(margin(l = 0 r = 3.1 b = 0 t = 0)) ///
    plotregion(margin(l = 0 r = 3.1 b = 0 t = 0) ///
    ilwidth(none) lwidth(none)) ///
    title("Trace of Estimated Regression Slope", size(huge)) ///
    xtitle("Iteration", size(vlarge)) ytitle("MCMC Draw", size(vlarge)) ///
    xlabel(, labsize(large)) ylabel(-20 "{&minus}20" -15 "{&minus}15" /// 
        -10 "{&minus}10" -5"{&minus}5" 0, labsize(large))


// Export the graph to SVG, replacing any existing version.
// N.B. SVG images don't hold embedded text (by default), but font metadata.
//      Whichever device opens them is responsible for correct text rendering.
local graph_path "`data_parent_directory'traceplot"
graph export "`graph_path'.svg", fontface("`custom_typeface'") replace

// Confirm the exported graph is accessible.
capture confirm file "`graph_path'.svg"
if _rc != `success' {
    prepare_exit "Unable to access graph (`graph_path'.svg), exiting."
    exit
}


// If Inkscape is installed, convert from SVG to PDF.
// N.B. Because Inkscape is being accessed via a script, and not via its
//      graphical user interface, invoke inkscape.com, not inkscape.exe.

local app_name "inkscape"
local drive_letter = substr("`c(pwd)'", 1, 1)
local user_name = c(username)

if "`c(os)'" == "Windows" {

    // Try and invoke Inkscape by getting its location from the Windows shell.
    // To read the shell result in Stata, save it to a temporary file, and
    // read that back into Stata. The temporary file will be auto-deleted.
    //
    tempfile shell_file
    tempname shell_handle
    shell where "`app_name'" > "`shell_file'"
    file open `shell_handle' using "`shell_file'", read text
    file read `shell_handle' shell_line
    file close `shell_handle'
    //
    if length("`shell_line'") > 0 {
        normalise_slashes "`shell_line'"
        local inkscape_path = r(normalised_val)
        //
        // Compose a path with ".com", not ".exe".
        local exe_target "`app_name'.exe"
        local exe_pos = strpos("`inkscape_path'", "`exe_target'")
        if `exe_pos' > 0 {
            local inkscape_path = subinstr("`inkscape_path'", ///
                "`exe_target'", "`app_name'.com", .)
        }
        //
        capture confirm file "`inkscape_path'"
        if _rc == `success' {
            shell "`inkscape_path'" --export-type="pdf" "`graph_path'.svg"
            prepare_exit
            exit
        }
    }

    // Check Inkscape's standard installation location.
    // (Non-virtualised environments.)
    local inkscape_path "`drive_letter':" ///
        "/Program Files/Inkscape/bin/inkscape.com"
    capture confirm file "`inkscape_path'"
    if _rc == `success' {
        shell "`inkscape_path'" --export-type="pdf" "`graph_path'.svg"
        prepare_exit
        exit
    }

    // Check for a per-user, portable Inkscape installation.
    // (Non-virtualised environments.)
    local inkscape_path "`drive_letter':" ///
        "/Users/`user_name'/AppData/Local/Programs/Inkscape/bin/inkscape.com"
    capture confirm file "`inkscape_path'"
    if _rc == `success' {
        shell "`inkscape_path'" --export-type="pdf" "`graph_path'.svg"
        prepare_exit
        exit
    }

    // Try and handle virtualised environments.
    //
    // Regex to match "/C$/" style virtual drives, allowing for an arbitrary
    //     drive letter.
    if regexmatch("${glb_data_full_path}", "/[a-zA-Z]\\$/") == 1 {

        // Add any necessary path prefix to the virtual drive.
        local drive_virtual = regexcapture(0)
        local drive_pos = strpos("${glb_data_full_path}", "`drive_virtual'")
        local drive_len = strlen("`drive_virtual'")
        local drive_virtual = substr("${glb_data_full_path}", 1, ///
            `drive_pos' + `drive_len' - 1)

        // Check Inkscape's standard installation location.
        // (Virtualised environments.)
        local inkscape_path "`drive_virtual'" ///
            "Program Files/Inkscape/bin/inkscape.com"
        capture confirm file "`inkscape_path'"
        if _rc == `success' {
            shell "`inkscape_path'" --export-type="pdf" "`graph_path'.svg"
            prepare_exit
            exit
        }

        // Check for a per-user, portable Inkscape installation.
        // (Virtualised environments.)
        local inkscape_path "`drive_virtual'" ///
            "Users/`user_name'/AppData/Local/Programs" ///
            "/Inkscape/bin/inkscape.com"
        capture confirm file "`inkscape_path'"
        if _rc == `success' {
            shell "`inkscape_path'" --export-type="pdf" "`graph_path'.svg"
            prepare_exit
            exit
        }

        // Check for a per-user, portable Inkscape installation, with
        //     opportunistic alternate username parsing. Specifically, check if
        //     "/Users/" appears in the path to the input water quality data,
        //     and try assuming the current username appears after it in that
        //     path.
        // (Virtualised environments.)
        //
        local users_target "/Users/"
        local users_pos = strpos("${glb_data_full_path}", "`users_target'")
        if `users_pos' > 0 {
            // Left trim the data path, up to and including "/Users/".
            local users_len = strlen("`users_target'")
            local user_name_alternate = substr("${glb_data_full_path}", ///
                `users_pos' + `users_len', .)

            // Right trim the remaining data path from the first "/" onwards.
            local slash_pos = strpos("`user_name_alternate'", "/")
            if `slash_pos' > 0 {
                local user_name_alternate = substr("`user_name_alternate'", ///
                    1, `slash_pos' - 1)
            }

            // Try the alternate username.
            local inkscape_path "`drive_virtual'" ///
                "Users/`user_name_alternate'/AppData/Local/Programs" ///
                "/Inkscape/bin/inkscape.com"
            capture confirm file "`inkscape_path'"
            if _rc == `success' {
                shell "`inkscape_path'" --export-type="pdf" "`graph_path'.svg"
                prepare_exit
                exit
            }
        }
    }

    // Tried to execute Inkscape but couldn't.
    local app_name = strproper("`app_name'")
    prepare_exit "Unable to access `app_name', exiting."
    exit

}    // End of Windows processing.
