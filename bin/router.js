#!/usr/bin/env node

require('babel/register')({
  // We need to do this so babel actually parses our files
  only: /frontendserver\/lib\/.*/
});
require('../lib/router.js');
