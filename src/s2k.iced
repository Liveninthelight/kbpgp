##  GPG4Browsers - An OpenPGP implementation in javascript
##  Copyright (C) 2011 Recurity Labs GmbH
##  
##  This library is free software; you can redistribute it and/or
##  modify it under the terms of the GNU Lesser General Public
##  License as published by the Free Software Foundation; either
##  version 2.1 of the License, or (at your option) any later version.
##  
##  This library is distributed in the hope that it will be useful,
##  but WITHOUT ANY WARRANTY; without even the implied warranty of
##  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
##  Lesser General Public License for more details.
##  
##  You should have received a copy of the GNU Lesser General Public
##  License along with this library; if not, write to the Free Software
##  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
## 
## @class
## @classdesc Implementation of the String-to-key specifier (RFC4880 3.7)
##  String-to-key (S2K) specifiers are used to convert passphrase strings
##  into symmetric-key encryption/decryption keys.  They are used in two
##  places, currently: to encrypt the secret part of private keys in the
##  private keyring, and to convert passphrases to encryption keys for
##  symmetrically encrypted messages.
##

#======================================================================

triplesec = require 'triplesec'
C = require './const'

{WordArray} = triplesec
{SHA1,SHA224,SHA256,SHA512} = triplesec.hash

#======================================================================

class S2K

  #----------------------

  _count : (c, bias) -> (16 + (c & 15)) << ((c >> 4) + bias)

  #----------------------
  
  constructor : () ->
    @hash_class = SHA256

  #----------------------

  set_hash_algorithm : (which) ->
    @hash_class = switch which
      when C.SHA1 then SHA1
      when C.SHA224 then SHA224
      when C.SHA256 then SHA256
      when C.SHA512 then SHA512
      else 
        console.warn "No such hash: #{which}; defaulting to SHA-256"
        SHA256

  #----------------------

  hash : (input) -> (new @hash_class).finalize(WordArray.from_buffer(input)).to_buffer()

  #----------------------
  
  # 
  # Parsing function for a string-to-key specifier (RFC 4880 3.7).
  # @param {Buffer} input Payload of string-to-key specifier
  # @param {Integer} position Position to start reading from the input string
  # @return {openpgp_type_s2k} Object representation
  # 
  read : (input, position) ->
    mypos = position
    @type = input.readUInt8 mypos++
    match = false

    switch @type  
      when 0 # Simple S2K
        #Octet 1: hash algorithm
        @set_hash_algorithm(input.readUInt8(mypos++))
        @s2kLength = 1
        match = true

      when 1 # Salted S2K
        # Octet 1: hash algorithm
        @set_hash_algorithm(input.readUInt8(mypos++))

        # Octets 2-9: 8-octet salt value
        @saltValue = input[mypos...(mypos+8)]
        mypos += 8
        @s2kLength = 9
        match = true

      when 3 # Iterated and Salted S2K
        # Octet 1: hash algorithm
        @set_hash_algorithm(input.readUInt8(mypos++))

        # Octets 2-9: 8-octet salt value
        @saltValue = input[mypos...(mypos+8)]
        mypos += 8
        @s2kLength = 9

        # Octet 10: count, a one-octet, coded value
        @EXPBIAS = 6
        c = input.readUInt8 mypos++
        @count = @_count c, @EXPBIAS
        @s2kLength = 10
        match = true


      when 101
        if input[(mypos+1)...(mypos+4)] is "GNU"
          @set_hash_algorithm(input.readUInt8(mypos++))
          mypos += 3  # GNU
          gnuExtType = 1000 + input.readUInt8 mypos++
          match = true
          if gnuExtType == 1001
            @type = gnuExtType
            @s2kLength = 5
            # GnuPG extension mode 1001 -- don't write secret key at all
          else
            console.warn "unknown s2k gnu protection mode! #{gnuExtType}"

    if not match
      console.warn("unknown s2k type! #{@type}")
      null
    else
      @
  
  #----------------------
  
  # 
  # writes an s2k hash based on the inputs.  Only allows type 3, which
  # is iterated/salted. Also default to SHA256.
  #
  # @return {Buffer} Produced key of hashAlgorithm hash length
  # 
  write : (passphrase, salt, c) ->
    @type = type = 3 
    @salt = salt
    @count = @_count c, 6
    @set_hash_algorithm C.SHA256
    @s2kLength = 10
    @produce_key passphrase

  #----------------------
  
  #
  # Produces a key using the specified passphrase and the defined 
  # hashAlgorithm 
  # @param {Buffer} passphrase Passphrase containing user input -- this is
  #   the UTF-8 encoded version of the input passphrase.
  # @return {Buffer} Produced key with a length corresponding to 
  # hashAlgorithm hash length
  #
  produce_key : (passphrase, numBytes) ->
    switch @type
      when C.s2k.plain then @hash passphrase
      when C.s2k.salt  then @hash Buffer.concat [ @salt, passphrase ]
      when C.s2k.salt_iter
        seed = Buffer.concat [ @salt, passphrase ]
        n    = Math.ceil (@count / seed.length)
        isp  = Buffer.concat( seed for i in [0...n])[0...@count]
        
        # This if accounts for RFC 4880 3.7.1.1 -- If hash size is greater than block size, 
        # use leftmost bits.  If blocksize larger than hash size, we need to rehash isp and prepend with 0.
        if numBytes? and numBytes in [24,34]
          key = @hash isp
          Buffer.concat [ key, @hash(Buffer.concat([(new Buffer [0]), isp ]))]
        else
          @hash isp
      else null

#======================================================================

s2k = new S2K()
console.log s2k.write(new Buffer("shit on me XXyy"), new Buffer([0...16]), 2048)

#======================================================================
