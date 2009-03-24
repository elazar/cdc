#!/usr/bin/php
<?php

/**
 * Ceres Document Checker
 *
 * Usage: cdc [OPTIONS] [PATTERN]
 *
 * Analyzes various aspects of a document in the Ceres format.
 *
 * PATTERN can be a file path, directory path, or pattern referring to one 
 * or more Ceres-formatted documents. Directory paths and patterns will 
 * automatically be recursed. If unspecified, defaults to the current 
 * directory. 
 *
 * OPTIONS:
 *    -a
 *        Article mode, implies -c 60 -l 10 -x
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

        case '-b':
            $climit = 70;
            $perpage = 375;
            break;

        case '-c':
            $climit = next($argv);
            if ($climit <= 0 || (int) $climit != $climit) {
                exit('cdc: Parameter to -c must be a positive integer, ' . $climit . ' was specified' . PHP_EOL);
            }
            break;

        case '-l':
            $llimit = next($argv);
            if ($llimit <= 0 || (int) $llimit != $llimit) {
                exit('cdc: Parameter to -l must be a positive integer, ' . $llimit . ' was specified' . PHP_EOL);
            }
            break;

        case '-p':
            $perpage = next($argv);
            if ($perpage <= 0 || (int) $perpage != $perpage) {
                exit('cdc: Parameter to -p must be a positive integer, ' . $perpage . ' was specified' . PHP_EOL);
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
        if (strpos($entry->getPath(), DIRECTORY_SEPARATOR . '.')) {
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

        // If the line ends a code block...
        } elseif (strpos($line, '</code>') === 0) {

            // If any PHP segments are found in the code block...
            if (preg_match_all('/<\?php.*(?:\?>|$)/UsS', $code, $matches)) {

                // Perform a lint check on the segments
                $code = implode('', $matches[0]);
                $response = shell_exec('echo ' . escapeshellarg($code) . ' | php -l');

                // If any syntax errors are found, display them
                if (strpos($response, 'No syntax errors detected') === false) {
                    $response = preg_replace(
                        '/in - on line ([0-9]+)$/e', 
                        '\'in ' . $file . ' on line \' . ($1 + ' . $start . ')',
                        trim(str_replace('Errors parsing -', '', $response))
                   );
                   echo $response, PHP_EOL;
                }
            }

            // If the line exceeds the specified line limit, display an error
            if (isset($llimit) && $length > $llimit) {
                echo 'Formatting error: Length ', $length, ' exceeds limit of ', $llimit, ' in ', $file, ' on line ', $start, PHP_EOL;
            }

            // Reset the starting point to indicate no code block is active 
            $start = 0;

        // If the line is within a code block...
        } elseif ($start) {

            // If the line exceeds the specified width limit, display an error 
            if (isset($climit) && $width > $climit) {
                echo 'Formatting error: Width ', $width, ' exceeds limit of ', $climit, ' in ', $file, ' on line ', $no, PHP_EOL;
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
                echo 'Found URL: ', $status, ' ', $address, PHP_EOL;
            } else {
                echo 'Failed ', $address, PHP_EOL;
            }
            sleep(0.5);
        }
    }

    // Display the word count for the current file
    echo 'File counts: ', counts($words, $perpage), ' in ', $file, PHP_EOL; 

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
