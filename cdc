#!/usr/bin/php
<?php

/**
 * Ceres Document Checker
 *
 * Usage: cdc [OPTIONS] [PATTERN]
 *
 * Analyzes various aspects of one or more documents in the Ceres format.
 *
 * PATTERN can be a file path, directory path, or pattern referring to one 
 * or more Ceres-formatted documents. Directory paths and patterns will 
 * automatically be recursed. If unspecified, it defaults to the current 
 * directory. 
 *
 * OPTIONS:
 *    -a
 *        Article mode, implies -c 60 -l 10 -x
 *    -A
 *        Include hidden files and directories, which are excluded by default
 *    -b
 *        Book mode, implies -c 70 -p 375
 *    -c # 
 *        Limit on the number of characters allowed per line within source 
 *        code blocks
 *    -l #
 *        Limit on the number of lines allowed within source code blocks
 *    -p #
 *        Number of words per page if page counts are desired
 *    -u
 *        Checks URLs and outputs the result of requesting them
 *    -x
 *        Excludes source code blocks from the word count
 */

// Parse arguments
$exclude = false;
$hidden = false;
$url = false;
$pattern = '*';
$perpage = null;

while (next($argv)) {
    $arg = current($argv);
    switch ($arg) {
        case '-a':
            $climit = 60;
            $llimit = 10;
            $exclude = true;
            break;

        case '-A':
            $hidden = true;
            break;

        case '-b':
            $climit = 70;
            $perpage = 375;
            break;

        case '-c':
            $climit = next($argv);
            if ($climit <= 0 || (int) $climit != $climit) {
                echo 'cdc: Parameter to -c must be a positive integer, ', $climit, ' was specified', PHP_EOL;
                exit(1);
            }
            break;

        case '-l':
            $llimit = next($argv);
            if ($llimit <= 0 || (int) $llimit != $llimit) {
                echo 'cdc: Parameter to -l must be a positive integer, ', $llimit, ' was specified', PHP_EOL;
                exit(1);
            }
            break;

        case '-p':
            $perpage = next($argv);
            if ($perpage <= 0 || (int) $perpage != $perpage) {
                echo 'cdc: Parameter to -p must be a positive integer, ', $perpage, ' was specified', PHP_EOL;
                exit(1);
            }
            break;

        case '-u':
            $url = true;
            break;

        case '-x':
            $exclude = true;
            break;

        default:
            $pattern = $arg;
            break 2;
    }
}

// Determine the target file(s) to analyze
if (is_file($pattern)) {
    $files = array($pattern);
} else {
    $dir = is_dir($pattern);
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($dir ? $pattern : '.')
    );
    $files = array();
    foreach ($iterator as $entry) {
        if (strpos($entry->getPathname(), DIRECTORY_SEPARATOR . '.') && !$hidden) {
            continue;
        }
        if ($entry->isFile() && ($dir xor fnmatch($pattern, $entry->getPathname()))) {
            $files[] = $entry->getPathname();
        }
    }
}
sort($files);

// Initialize the starting point of the current code block (0 for none)
$start = 0;

// Initialize a total word count accumulator 
$totalwords = 0;

// For each file...
foreach ($files as $file) {

    // Initialize a word accumulator
    $words = 0;

    // Initialize a flag indicating a PHP code block 
    $php = false;

    // Output the file path
    echo $file, PHP_EOL;

    // For each line in the current file...
    foreach (file($file) as $key => $line) {

        // Get the line number and width 
        $no = $key + 1;
        $width = strlen(rtrim($line));

        // If the line starts a code block...
        if (strpos($line, '<code') === 0) {

            // Store the current line number
            $start = $no;

            // Initialize a line counter
            $length = 0;

            // Reset the code buffer
            $code = '';

            // Reset the PHP code block flag
            $php = (strpos($line, ' php>') !== false);

        // If the line ends a code block...
        } elseif (strpos($line, '</code>') === 0) {

            // If any PHP segments are found in the code block...
            if (preg_match_all('/<\?php.*(?:\?>|$)/UsS', $code, $matches)) {

                // If the block is not flagged as PHP, output a notice and continue
                if (!$php) {
                    echo $start, ': NOTICE - Code block not specified as PHP, but contains PHP tags', PHP_EOL;

                // If the block is PHP code...
                } else {

                    // Perform a lint check on the segments
                    $code = implode('', $matches[0]);
                    $process = proc_open('php -l', array(0 => array('pipe', 'r'), 1 => array('pipe', 'w')), $pipes);
                    fwrite($pipes[0], $code);
                    fclose($pipes[0]);
                    $response = stream_get_contents($pipes[1]);
                    fclose($pipes[1]);
                    proc_close($process);

                    // If any syntax errors are found, display them
                    if (strpos($response, 'No syntax errors detected') === false
                        && preg_match('/in - on line ([0-9]+)/', $response, $match)) {
                        $errline = (int) $match[1] + $start;
                        $response = trim(str_replace(
                            array('Errors parsing -', 'syntax error, ', $match[0]),
                            array('', '', ''),
                            $response
                        ));
                        echo $errline, ': ERROR - ', $response, PHP_EOL;
                    }
                }
            }

            // If the line count exceeds the specified line limit, display an error
            if (isset($llimit) && $length > $llimit) {
                echo $no, ': ERROR - Line count ', $length, ' exceeds limit of ', $llimit, PHP_EOL;
            }

            // Reset the starting point to indicate no code block is active 
            $start = 0;

        // If the line is within a code block...
        } elseif ($start) {

            // If the line exceeds the specified width limit, display an error 
            if (isset($climit) && $width > $climit) {
                echo $no, ': ERROR - Line width ', $width, ' exceeds limit of ', $climit, PHP_EOL;
            }

            // Increment a line counter
            $length++;
            
            // Add the line to the code buffer
            $code .= $line;
        }
        
        // Add to word counts if necessary 
        if (!$exclude || !$start) {
            $words += count(explode(' ', $line));
        }

        // If the line contains a URL, confirm it is accessible
        if ($url && preg_match('/http:\/\/[\w\/.?&=\-]+/', $line, $match)) {
            $address = rtrim($match[0], '.');
            if ($fp = @fopen($address, 'r')) {
                $meta = stream_get_meta_data($fp);
                $status = explode(' ', $meta['wrapper_data'][0]);
                $status = $status[1];
                echo $start, ': NOTICE - Found URL ', $address, ' with response status ', $status, PHP_EOL;
            } else {
                echo $start, ': ERROR - Found URL ', $address, ' but could not access', PHP_EOL;
            }
            sleep(0.5);
        }
    }

    // Display the word count for the current file
    echo 'Counts: ', counts($words, $perpage), PHP_EOL, PHP_EOL;

    // Update the total word count accumulator
    $totalwords += $words;
}

// Output the word count
echo 'Total counts: ', counts($totalwords, $perpage), PHP_EOL;

/**
 * Returns a word count and optional page count given a total word count.
 *
 * @param int $words Total word count
 * @param int|null $perpage Optional word limit per page
 * @return string Formatted page and word count
 */
function counts($words, $perpage = null) {
    if ($perpage) {
        $return = floor($words / $perpage) . ' pages + ' . ($words % $perpage) . ' words';
    } else {
        $return = number_format($words) . ' words';
    }
    return $return;
}
