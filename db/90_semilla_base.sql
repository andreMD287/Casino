-- 90_semilla_base.sql (André) — GENERADO por scripts/generar-usuarios-semilla.ts. No editar a mano.
-- Usuarios de prueba (clave de todos: Casino2026*), juegos y opciones de apuesta.
SET ROLE casino_owner;
SET search_path = casino, public;

-- Usuarios (salt y verificador SRP-6a con SHA-256; la clave no se guarda).
DO $$
BEGIN
  PERFORM fn_crear_usuario('admin', 'd91f9c45b2dffce95751ddeb944382b095a46379fad0d8995916a0be2190e03a',
    '11374da43470eecab7d772f76597f7136805f0091cea4b9d20f84e89a14ecaedf53ca746333662221373386bb86966e47ea00f9436b357593498dd7610a6972f2518547743ad4bc5342fbdf9c35b5aa3ec577de5eea11fc05148d3a7fa99719e9ef4d251c586b708b7dcbb6b0f4cf4ca32c912d01cfef073d09d63303c2c249231bd6c9ef74a988c7b422d9a80d9a5eca2572a5919eff2c5a75a9aa88d9720f453ed867b86f61b75c2cb227b90036e3c1850460c5ac7025f7ad7b49dc807712fdd20e97674a2aaecd49bc8005e0eab7a0356da7172e880dd038b84b450936ffae3d16e034274611f68e24183445f54487365ccf7b48598e00258c7259e44ac19', 'administrador');
  PERFORM fn_crear_usuario('crupier1', '50ed491f5d1551ccabdb89a6aa26ee719776d28ead66aa874c7039c6b2978d43',
    '1258d1fd1e1d371b6ad8badf9e66235c8115bff6825fb46188a70b3bf2478548ae6bcb27b7a3584fda518863dbbb449e5481808a54b27453886c59e330c0fae1209826ddd75bb597d640fdbfe46d9b0b08e269eae057ad9ff23a59ee37ca550b70d98ada25388ca42e943101a5c1f967f545586a8c23ea4d47e6e584fb848af7b6353e91e31340a95181a900a7f03b68130857e4340e9e69f7d2e370a539e48d1c731c83563619d6894afa4959804de7eaa50a7b0ad26c49a8d550d09c4bb8b2f5726b587581ad3958866d46bcdc20f29713af8a804208aa58e0f29c22876a941435d4b5ab9041da534f204ba1fe093f318e4b1c09bca9a111744f55d4fecca5', 'crupier');
  PERFORM fn_crear_usuario('crupier2', '807a63253428a09054bcccb5a5e7c58fb4f686c7bda2e7528294ee4fbaf31b21',
    '500b1875221e1af923597ff8b8aa94511ecebffdf7e19244e2d2c4883710a37db497d9010401574282fb759ecd5c78d20e09208c5b2016ca92aef6b01763a3b829c7e3c7b159d59b3430150b3e8a15e679e5c61071ea0aa8a2ff609541fedb9042df314589560e147783ba9661e667ea4ba9eb69351047e7486595205ec7867ac93f19989d955031425c63e42287833782a39574cdc6269f371ae9bd7f38112b2dcd4f47b65ed67ca1d4b1b88beab567462e86fae38843445175993880df280224a7507e4bface7afdded257b501fe083ae5e4a88e65a790cf35280827ac71a4a94b9a37ee1403b3857dcc2f851cefcbb52fa70bde1f9a579ae3f1bc457fad2c', 'crupier');
  PERFORM fn_crear_usuario('crupier3', '3d3b2c8292c55f34f0e0ad8e97f408505204fd298c45eb94f4c674f16fa14f76',
    '2e747908bd293f460791a788e4289cce46cf4b3ecd10a6a4eafe6683ce5e4013e9a58219683eca202876f4fc0b46fb04aaf3a5224594385973c14813c3bc6ce15cb260a8f62de897800fb5ccd07cc12330f2c55418db7c35d9a3a220f177d13e8f40a22ba237a9baa673504dc294f98c5d26843c6c843ce7a7775be5cadb6602d13ef999626bc8930b5ea8cd8647a12b29b0fa05392af1fd687221896bcd2d8122f4b67c3f90ad1a3b903cccec492eb30ab6e2959efc934ba55bd4ee47e4ee03965aa9148b3442a3002adb73b002d5b8912b5f774de7319c4b145b72e95ffbb459dd661db8def87a925d4ba89c36b0dd36c2e16610cca389ea05d95b162429d6', 'crupier');
  PERFORM fn_crear_usuario('crupier4', 'd71fcdb85cbd7f2138a21e38cd7835c8c703b9b9f8b4708e5b7f9208ec4b350a',
    '911e1af5dd14b85a18b5035fc7b9efb49f24378c3a31d4e11447241dbd7bd479d9769fd49c70ba592f83531331566d5fbbedc11c50f74606f72874c2178d88e22e60fceed3bfddc20b89fa960ca72807f9f3be372259e8f5978471971506080869cb60968e20c09fa2ab8b36f04313a0876d36c235ef3944e32b9bb1a6634ae31124fc48d6fb4c5ae50129601423ac5c9957c84d7c8e7634901e4150170fb80c0b491438fc92a4da50078f6b7138581b673ea9fec75d2e9f54c4a257fcaff50c2ef18302f9a2dec8c0cb83ef6729043a2478b243da8fa992ece97ade4a87c577df93b644177ac13358bc60c3ff842ae4c52ea06961bd2fc0cedaed263922173b', 'crupier');
  PERFORM fn_crear_usuario('supervisor1', 'af1f59b6bf88c0063b1e9404f54f407be5e0072c74bf051827c68cb0bb6aefab',
    '7a317bae2f14030b8e4d2c54dbb7ebe67caa0dc81c1cd8c2a8c59ef21f7b0b669ecbc7f805d46fc46edb016a1f5fb5646128b0250a5b09c9e4cf130908c94512a8df4a674e2ea4d8fbe5fd3437eab60895798a33747f16c97952f67cbd22d3231b98a8eada2af4cd3d4cf87d47f5afbdef0c967c2461a5cf302348e9292bd3c0d09a03bb142b8a73d9d0585cf2688bbf86e81f42113aca9053e41f1dfbf822b0c9b95c3514e4506a4377644229b19a9b0618713e1013a2e2fda026421468935d7209caff25528a7a334ba8ae2f86f251895ee40854a480dd33bc208bf79c11c7b7b110b89de1d8caf70b6cc2bdb0764e17b57d4e9055fea645df493b04bc5b0c', 'supervisor');
  PERFORM fn_crear_usuario('supervisor2', 'f28d5ad69b0172a9d9a5e483cf09160959723405cdb1c6bb955372c47a4c22e2',
    '765feec327a006b7f481e0accfa8cf0053c589161db54eba37c2ba122ba9e1c8618757cb96703cf4b67ba607818b0f8a95bd2eddb0eba8c17cdc154474028cfcdce2af461bb8fe029d5287e9befc0da75621e656cbc5e99938d8a41a1ef0fb6b1cdbf3d7b2f128717cf6ca5e69a6b5afb04e63da462663f0788c105db834431c71c900778f3566ac8395a00ace8d922ff0180a78c2f4d8634c8b8bd2b98d14b37c1287f842dac5fc66f5a2b2bf4018d3da312ea6e889a86e4a1090a9563fac006b333b83771e8634a9e80a8d87ed22aac2e552ccd8fd0c0cd9d6d4a0862d40645080120dd4af651a0881846cc582ab24633b60103c05352857a89f595f970b0b', 'supervisor');
  PERFORM fn_crear_usuario('jugador1', 'db84393dedbac0932d70276d7165eeab57afd61b7989ef1edf098a9792b4cef2',
    '9aa1af6819163896f2d7d42cc6366a4344574c02d608d2680feade07568fab437f6e0cea45cb6f1e3886b825f997c00172f2f33e5a2a13d181a2d0f6db6bbb9a47fb0b3d0ab32d6c9760f6753c579ac4fc7455417d8a7699c4397acbec8383d81628dabec74263eba7a6f3ab441945234c72ca359faee39469a4f58a7038e438af0300d6518703411eeb23c0085ab6b954fe905794f9b0899c054fd9ba3a59bcdebecbe25274aa4dff33692210fa5f1e439791700635718bd734cb9f2740d38ed3431877dbf18740dec311b91781ae3043b4634e5b249b506dff3f427109f1fea417a007a1f5ca0836024ec51279d6afb9c5f69ebf0cd0bfa7b6f1539df10cd2', 'jugador');
  PERFORM fn_crear_usuario('jugador2', '78705c6965964ec23f7b5b325172ecac3e6ce1596921a6742a7dcf304e4eb414',
    '319ee4b7fa56584953343eb28ed7b4280c90240a675004f4a9e4f47c436c0bcf829d11d6256c75dbb81b4dfcaf6be817ca0046c7ab176fe172b0b0f0dc662262495081f92e256290bbdc8855a9ba18cc4834af175d66b19bbc12d6c6cc01ede3ac15c6f35326600342f77eb70acdcd338b2c93d232375df2468f570573551d0efe83fecd0945380e36e28bf37a5ae3898f2d9b16628af61b3ff0b78e40e7ee1231b968776e73f7b03ae8e6d795af53e1e86ccc482f14f4998cd311617afb36f6105b6f064d1d1e7fa95935c5f7a01cd0958e3ee5ddd661ca26b21520682fb1223279dc30bc419cbe8369446483e67b4ee31cdd0f2d9eaa985d29dc2a5e2fe8d5', 'jugador');
  PERFORM fn_crear_usuario('jugador3', 'fee129cc10b6a7268b4e6e9ee1cfe99c87a46616674215ac5ef86c0eefe9d2f0',
    'aa6105850f2c34b90e453e8b20c9167fa860aac9722c23b8b0089cd419572919fb51d88ca122604d699e0f99b9fdfa49f9379c68f6e18a7f32e73a972fbe15e60f9d184d019e1f04c52c50f85c906d453d651bfadd77395c9d03e44c52c93bc0ed822546a652cc60824857be96cd0ec881600a268f78ef3bae09430ac8b7af1ab39c71cb4768b1aa95054f22aae810cedab3410e06efb4ea4798fa93e2373911a87f69513e809efd4643fbaf16de8d4fcef031bec28b8d5f76d072c10c03816181d43d76c493f36be7508217a9dd3887b3f0cd56bdcccd0c1e4328d6c6c21bad78fea425b83f550ae88de0f07b60314d6304f8b944b93258c5a35d200df39324', 'jugador');
  PERFORM fn_crear_usuario('crupier1.juega', 'ef2490602d54818960fad92a13def89aae6ef51a666dca5aee8e9467d34dda47',
    '73ffbb7e6118662cbefe7e1f86fbfb43c0524f8abaade43f0e6d9b208d45cecb1e84733ab051b88c3f977a4ecfc17c9d63f6aa66e8632ef8fa4cf5c12ef5c0cb08b3a730392821a7303dd01bc4c44bf81cf34455e5052d360516ff2d6be22a4425b405f5d09a90318e4370abf88c98cb5a924e59997a4ab7e3d26a168f8ff5b03440ef2aaa02bc48fc7aaa27bd4149ebe10fd0edf7cbaa8167f72813c624836846afd5ff809b2c4e437ea36493e067e1b982adc46378848b9b9a68b8027644b82829148094d861c3cbd0b67dd8389fda04e7b5ca22c9f7b853ff05d9a3dd8f8907dfa51ed08452bb74a254acdd58a75cadbe543daad3847b69432d2ea2c46344', 'jugador');
  PERFORM fn_crear_usuario('supervisor1.juega', '14a4554ea4ea093992e6d23911c39efabc61177b65979ad923d98d8c8f670979',
    '890aa31e4fe8dae3dc78640d3ba49b75259f82ac9d7d711cdd7419ce0cbe7c56d29d01a1dbf0694fc91a02b5cdf26f57755cbf115645c507adf332a3d72e6c9c9b94b1345a73630c6ac452e1ae51d22a6b9aa8b9ba56dde2fa0ba7b0c6274a9615a4551c9ce8e589769173152983fe8bde20f7ee31759f6578b4d70bb613670ee3d03a64d983c63e6cc9dfb44f30a1e053049b434001225c0648d09759aa0fd3d749dc287a0cbb7636bdb5bc9330d9c10d0a665124bd736c49cc47a29ad2b9d0726b1979bc3ca65b775e89224310ee8689974a178cb6ae3f9add919b040bba0e5d1d9718361abda21ba56e3de93ae900fcdf1532ffdd6c55aca6533fae2188c2', 'jugador');
END
$$;

-- Juegos
INSERT INTO juegos (nombre, registro_detallado) VALUES
  ('Ruleta', true),
  ('Blackjack', true),
  ('Póker', false);

-- Opciones de apuesta (factor de pago: premio = monto × factor)
INSERT INTO opciones_apuesta (juego_id, nombre, factor_pago) VALUES
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 0', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 1', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 2', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 3', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 4', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 5', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 6', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 7', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 8', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 9', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 10', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 11', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 12', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 13', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 14', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 15', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 16', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 17', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 18', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 19', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 20', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 21', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 22', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 23', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 24', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 25', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 26', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 27', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 28', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 29', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 30', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 31', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 32', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 33', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 34', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 35', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Pleno 36', 35),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Rojo', 1),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Negro', 1),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Par', 1),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Impar', 1),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Primera docena', 2),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Segunda docena', 2),
  ((SELECT id FROM juegos WHERE nombre = 'Ruleta'), 'Tercera docena', 2),
  ((SELECT id FROM juegos WHERE nombre = 'Blackjack'), 'Mano ganadora', 1),
  ((SELECT id FROM juegos WHERE nombre = 'Blackjack'), 'Blackjack', 1.5),
  ((SELECT id FROM juegos WHERE nombre = 'Póker'), 'Mano ganadora', 1);
